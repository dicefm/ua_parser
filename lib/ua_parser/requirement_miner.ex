defmodule UAParser.RequirementMiner do
  @moduledoc """
  Derives, from a pattern's regex source, a *requirement*: a literal that any
  matching string must contain. This is offline, maintainer-facing tooling -
  it runs once, from `mix ua_parser.gen_requirements`, whenever
  `priv/patterns.yml` changes. The result is checked into
  `priv/requirements.exs` and loaded by `UAParser.Storage` at boot, so none
  of this module's code runs in the parse hot path; `UAParser.Index` only
  ever consumes its output.

  Deriving a requirement is two passes:

    * `tokenize/1` reads the regex source's syntax (escapes, character
      classes, groups, alternation, quantifiers) into a small tree of
      `t:token/0`, with no opinion about which parts are worth indexing.
    * `analyze/1` walks that tree computing the longest literal run that
      must be present, folding classes and harvesting alternations along
      the way, with no opinion about regex syntax.

  Splitting the two keeps each independently testable: tokenizer tests
  check the tree a given source produces, analyzer tests check what
  requirement a given tree yields, and `requirement/1`'s own tests check
  the two composed.

  A requirement is one of:

    * `{:all, literal}` - `literal` must be present, e.g. `"Chrome/"` for
      `Chrome/(\\d+)\\.(\\d+)`
    * `{:any, literals}` - at least one of `literals` must be present, from
      an alternation like `(Googlebot|Bingbot)/(\\d+)`
    * `nil` - nothing could be proven; the pattern is always tested

  ## Correctness

  A requirement may only ever *narrow* the set of strings it accepts; it
  must never exclude a string that could match. Every rule below is
  therefore conservative: anything that cannot be proven yields `nil`,
  which falls back to always testing that pattern. Specifically, a literal
  run is broken by anything optional or variable (quantifiers, wildcards,
  ranges and negated classes), group contents are only mined when the
  group is mandatory, and lookarounds are never mined at all. A class is
  mined only when every one of its members folds to the same character.

  Literals are matched case-insensitively: they are folded when mined and
  the subject is folded once per call by `UAParser.Index`. That costs one
  pass over the string and makes requirements slightly less selective, but
  it lets a class like `[Bb]` pin a character, which is worth far more
  than it costs.
  """

  # A required literal has to be distinctive to be worth indexing; a one or
  # two character string appears in almost every user agent. Three is where
  # it starts paying: it is what "bot" needs, and that one literal alone
  # decides a pattern that costs 12 us to fail.
  @min_all_length 3
  @min_any_length 3

  # Characters that are only escaped to strip their regex meaning, so the
  # escaped form stands for the literal character.
  @escaped_literals ~c".\\+*?()[]{}|^$/-"

  @typedoc """
  One piece of a tokenized branch:

    * `{:lit, char}` - a literal character
    * `{:fold, char}` - a character class whose members all fold to `char`
    * `:anchor` - `^` or `$`, zero-width, never breaks a run
    * `:break` - anything that breaks a run and contributes nothing: a
      wildcard, an unrecognised escape, a class that cannot be folded, a
      lookaround/named group, or a quantified atom (which may vanish or
      repeat, so it cannot reliably extend a run)
    * `{:group, scope}` - a mandatory (unquantified) group
  """
  @type token :: {:lit, binary()} | {:fold, byte()} | :anchor | :break | {:group, scope()}

  @typedoc "A group's content: one branch, or several split on a top-level `|`."
  @type scope :: {:one, [token()]} | {:any, [[token()]]}

  @type requirement :: {:all, binary()} | {:any, [binary()]} | nil

  @doc """
  Derives the requirement a string must satisfy for `source` (a regex
  source, as returned by `Regex.source/1`) to have any chance of matching.

  Returns `nil` when nothing can be proven.

  ## Examples

      iex> UAParser.RequirementMiner.requirement("Chrome/(\\\\d+)\\\\.(\\\\d+)")
      {:all, "chrome/"}

      iex> UAParser.RequirementMiner.requirement("(Googlebot|Bingbot)/(\\\\d+)")
      {:any, ["googlebot", "bingbot"]}

      iex> UAParser.RequirementMiner.requirement("[Ss]pider/(\\\\d+)")
      {:all, "spider/"}

      iex> UAParser.RequirementMiner.requirement("(\\\\d+)|(\\\\w+)")
      nil

  """
  @spec requirement(binary()) :: requirement()
  def requirement(source) do
    case tokenize(source) do
      :unprovable -> nil
      {:ok, nodes} -> nodes |> analyze() |> pick_requirement()
    end
  end

  defp pick_requirement({best, any_sets}) do
    [{:all, best} | Enum.map(any_sets, &{:any, &1})]
    |> Enum.filter(&viable?/1)
    |> Enum.max_by(&selectivity/1, fn -> nil end)
    |> fold_case()
  end

  # --- tokenize: regex source -> tree -------------------------------------

  @doc """
  Reads a regex source's syntax into a tree of `t:token/0`, with no opinion
  about which parts are worth indexing. Returns `:unprovable` only for a
  bare top-level alternation (`A|B` with no enclosing group) - the same
  case `analyze/1` would find nothing usable in, surfaced earlier so
  callers do not need to invent a "root scope" to hold it.
  """
  @spec tokenize(binary()) :: {:ok, [token()]} | :unprovable
  def tokenize(source), do: tokenize_branch(source)

  defp tokenize_branch(<<>>), do: {:ok, []}
  defp tokenize_branch(<<"|", _rest::binary>>), do: :unprovable

  defp tokenize_branch(<<"\\", escaped, rest::binary>>) do
    if escaped in @escaped_literals do
      continue({:lit, <<escaped>>}, rest)
    else
      emit(:break, rest)
    end
  end

  defp tokenize_branch(<<"[", rest::binary>>) do
    {class, remaining} = take_class(rest, <<"[">>)

    case class_literal(class) do
      {:ok, char} -> continue({:fold, char}, remaining)
      :error -> emit(:break, remaining)
    end
  end

  defp tokenize_branch(<<"(?:", rest::binary>>), do: tokenize_group(rest)

  # Lookarounds and named groups: never mined, whatever follows them.
  defp tokenize_branch(<<"(?", _rest::binary>> = source) do
    <<"(", rest::binary>> = source
    {_content, after_close} = group_span(rest)
    emit(:break, skip_quantifier(after_close))
  end

  defp tokenize_branch(<<"(", rest::binary>>), do: tokenize_group(rest)
  defp tokenize_branch(<<".", rest::binary>>), do: emit(:break, rest)
  defp tokenize_branch(<<anchor, rest::binary>>) when anchor in [?^, ?$], do: emit(:anchor, rest)

  # A bare quantifier or brace, reached only when nothing we just tokenized
  # was worth peeking after (a non-foldable class, a group, a lookaround) -
  # the run is already flushed, so this is a no-op skip, not a new break.
  defp tokenize_branch(<<quantifier, rest::binary>>) when quantifier in [?*, ?+, ?\?],
    do: tokenize_branch(skip_quantifier(<<quantifier, rest::binary>>))

  defp tokenize_branch(<<"{", rest::binary>>), do: tokenize_branch(skip_to_brace(rest))
  defp tokenize_branch(<<char, rest::binary>>), do: continue({:lit, <<char>>}, rest)

  # A character or fold immediately followed by a quantifier may repeat or
  # vanish, so it cannot reliably extend a run: it becomes a break instead
  # of being emitted at all.
  defp continue(_node, <<quantifier, _rest::binary>> = source) when quantifier in [?*, ?+, ?\?, ?{],
    do: emit(:break, skip_quantifier(source))

  defp continue(node, rest), do: emit(node, rest)

  defp emit(node, rest) do
    case tokenize_branch(rest) do
      :unprovable -> :unprovable
      {:ok, nodes} -> {:ok, [node | nodes]}
    end
  end

  defp tokenize_group(rest) do
    {content, after_close} = group_span(rest)

    # Only a group that appears exactly once is mined. A quantified one may
    # vanish or repeat, and reasoning about where its content lands is not
    # worth the risk of getting it wrong.
    if quantified?(after_close) do
      emit(:break, skip_quantifier(after_close))
    else
      emit({:group, tokenize_scope(content)}, after_close)
    end
  end

  # Splits a group's content on its top-level `|` and tokenizes each branch.
  # Every branch here is already `|`-free, so `tokenize_branch/1` cannot
  # return `:unprovable` for it.
  defp tokenize_scope(content) do
    case split_alternatives(content, 0, <<>>, []) do
      [only_one] -> {:one, tokenize_branch!(only_one)}
      alternatives -> {:any, Enum.map(alternatives, &tokenize_branch!/1)}
    end
  end

  defp tokenize_branch!(source) do
    {:ok, nodes} = tokenize_branch(source)
    nodes
  end

  defp split_alternatives(<<>>, _depth, current, acc), do: Enum.reverse([current | acc])

  defp split_alternatives(<<"\\", escaped, rest::binary>>, depth, current, acc),
    do: split_alternatives(rest, depth, <<current::binary, "\\", escaped>>, acc)

  defp split_alternatives(<<"[", rest::binary>>, depth, current, acc) do
    {class, remaining} = take_class(rest, <<"[">>)
    split_alternatives(remaining, depth, <<current::binary, class::binary>>, acc)
  end

  defp split_alternatives(<<"(", rest::binary>>, depth, current, acc),
    do: split_alternatives(rest, depth + 1, <<current::binary, "(">>, acc)

  defp split_alternatives(<<")", rest::binary>>, depth, current, acc),
    do: split_alternatives(rest, max(depth - 1, 0), <<current::binary, ")">>, acc)

  defp split_alternatives(<<"|", rest::binary>>, 0, current, acc),
    do: split_alternatives(rest, 0, <<>>, [current | acc])

  defp split_alternatives(<<char, rest::binary>>, depth, current, acc),
    do: split_alternatives(rest, depth, <<current::binary, char>>, acc)

  # Returns the group's content and what follows its closing paren, with any
  # trailing quantifier left in place for `quantified?/1` to inspect.
  defp group_span(source), do: group_span(source, source, 0)

  defp group_span(<<"\\", _escaped, rest::binary>>, source, depth), do: group_span(rest, source, depth)
  defp group_span(<<"[", rest::binary>>, source, depth), do: group_span(skip_class(rest), source, depth)
  defp group_span(<<"(", rest::binary>>, source, depth), do: group_span(rest, source, depth + 1)

  defp group_span(<<")", rest::binary>>, source, 0),
    do: {binary_part(source, 0, byte_size(source) - byte_size(rest) - 1), rest}

  defp group_span(<<")", rest::binary>>, source, depth), do: group_span(rest, source, depth - 1)
  defp group_span(<<_char, rest::binary>>, source, depth), do: group_span(rest, source, depth)
  defp group_span(<<>>, source, _depth), do: {source, <<>>}

  defp quantified?(<<quantifier, _rest::binary>>) when quantifier in [?*, ?+, ?\?, ?{], do: true
  defp quantified?(_after_close), do: false

  defp skip_quantifier(<<quantifier, rest::binary>>) when quantifier in [?*, ?+, ?\?], do: rest
  defp skip_quantifier(<<"{", rest::binary>>), do: skip_to_brace(rest)
  defp skip_quantifier(rest), do: rest

  defp skip_to_brace(<<"}", rest::binary>>), do: rest
  defp skip_to_brace(<<_char, rest::binary>>), do: skip_to_brace(rest)
  defp skip_to_brace(<<>>), do: <<>>

  defp skip_class(<<"\\", _escaped, rest::binary>>), do: skip_class(rest)
  defp skip_class(<<"]", rest::binary>>), do: rest
  defp skip_class(<<_char, rest::binary>>), do: skip_class(rest)
  defp skip_class(<<>>), do: <<>>

  defp take_class(<<"\\", escaped, rest::binary>>, acc), do: take_class(rest, <<acc::binary, "\\", escaped>>)
  defp take_class(<<"]", rest::binary>>, acc), do: {<<acc::binary, "]">>, rest}
  defp take_class(<<char, rest::binary>>, acc), do: take_class(rest, <<acc::binary, char>>)
  defp take_class(<<>>, acc), do: {acc, <<>>}

  # A class whose members all fold to the same character - [Bb], [gG] - picks
  # that one character whatever the case, so it can extend a run rather than
  # breaking it. This is what makes `[Bb]ot` and `[Ss][Pp][Ii][Dd][Ee][Rr]`
  # provable. Ranges, negation and shorthands stay unprovable.
  defp class_literal(class) do
    inner = binary_part(class, 1, byte_size(class) - 2)

    with {:ok, members} <- class_members(inner, []),
         [<<char>>] <- members |> Enum.map(&String.downcase/1) |> Enum.uniq() do
      {:ok, char}
    else
      _other -> :error
    end
  end

  defp class_members(<<>>, []), do: :error
  defp class_members(<<>>, members), do: {:ok, members}
  defp class_members(<<"^", _rest::binary>>, []), do: :error
  defp class_members(<<"-", _rest::binary>>, _members), do: :error

  defp class_members(<<"\\", escaped, rest::binary>>, members) when escaped in @escaped_literals,
    do: class_members(rest, [<<escaped>> | members])

  defp class_members(<<char, rest::binary>>, members) when char < 128,
    do: class_members(rest, [<<char>> | members])

  defp class_members(_other, _members), do: :error

  # --- analyze: tree -> requirement ----------------------------------------

  @doc """
  Walks a tokenized branch computing the longest literal run that must be
  present, plus any alternation sets harvested from mandatory groups along
  the way. Has no opinion about regex syntax - `tokenize/1` has already
  resolved all of that into `t:token/0`.
  """
  @spec analyze([token()]) :: {binary(), [[binary()]]}
  def analyze(nodes), do: analyze(nodes, <<>>, <<>>, [])

  defp analyze([], run, best, anys), do: {longer(run, best), anys}
  defp analyze([:anchor | rest], run, best, anys), do: analyze(rest, run, best, anys)
  defp analyze([:break | rest], run, best, anys), do: analyze(rest, <<>>, longer(run, best), anys)
  defp analyze([{:lit, char} | rest], run, best, anys), do: analyze(rest, run <> char, best, anys)
  defp analyze([{:fold, char} | rest], run, best, anys), do: analyze(rest, run <> <<char>>, best, anys)

  defp analyze([{:group, scope} | rest], run, best, anys) do
    flushed = longer(run, best)

    # A literal from inside a group is never joined to the text around it -
    # we cannot prove where inside the group it sits - so it only competes
    # as a candidate of its own. Any-sets found nested inside the group are
    # still required by it, so they come up with it.
    case analyze_scope(scope) do
      {:one, literal, nested} -> analyze(rest, <<>>, longer(flushed, literal), nested ++ anys)
      {:any, literals} -> analyze(rest, <<>>, flushed, [literals | anys])
      :unprovable -> analyze(rest, <<>>, flushed, anys)
    end
  end

  defp analyze_scope({:one, nodes}) do
    {best, anys} = analyze(nodes)
    {:one, best, anys}
  end

  # Every branch must yield a non-empty literal, otherwise a string could
  # match through the branch that did not.
  defp analyze_scope({:any, branches}) do
    literals =
      Enum.reduce_while(branches, [], fn nodes, acc ->
        case analyze(nodes) do
          {best, _anys} when best != <<>> -> {:cont, [best | acc]}
          _unprovable -> {:halt, :unprovable}
        end
      end)

    case literals do
      :unprovable -> :unprovable
      literals -> {:any, literals |> Enum.reverse() |> Enum.uniq()}
    end
  end

  defp longer(a, b) when byte_size(a) >= byte_size(b), do: a
  defp longer(_a, b), do: b

  # Requirements are matched case-insensitively. Folding can only ever make
  # the requirement weaker - a literal that was present in some casing is
  # still present once both sides are folded - so it cannot exclude a
  # pattern that would have matched.
  defp fold_case(nil), do: nil
  defp fold_case({:all, literal}), do: {:all, String.downcase(literal)}

  defp fold_case({:any, literals}),
    do: {:any, literals |> Enum.map(&String.downcase/1) |> Enum.uniq()}

  defp viable?({:all, literal}), do: byte_size(literal) >= @min_all_length
  defp viable?({:any, []}), do: false
  defp viable?({:any, literals}), do: Enum.all?(literals, &(byte_size(&1) >= @min_any_length))

  # How good a filter this requirement is, approximated by the shortest
  # string we would be searching for: an "any of" set is only as selective
  # as its weakest member.
  defp selectivity({:all, literal}), do: byte_size(literal) * 2
  defp selectivity({:any, literals}), do: literals |> Enum.map(&byte_size/1) |> Enum.min()
end
