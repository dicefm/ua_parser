defmodule UAParser.Index do
  @moduledoc """
  A precomputed index over one of the pattern lists, used to skip regexes
  that cannot possibly match a given user-agent string.

  Matching a user agent means finding the first pattern in an ordered list
  whose regex matches. Done naively that runs every regex in the list until
  one hits - 362 user-agent, 201 OS and 633 device patterns in the bundled
  `patterns.yml`. Most of those regexes cannot match a given string at all,
  and some are expensive to fail (large alternations, or lazy `.{0,200}?`
  prefixes that backtrack heavily before giving up).

  So for each pattern we derive, from its regex source, a *requirement*: a
  literal that any matching string must contain.

    * `{:all, literal}` - `literal` must be present, e.g. `"Chrome/"` for
      `Chrome/(\\d+)\\.(\\d+)`
    * `{:any, literals}` - at least one of `literals` must be present, from
      an alternation like `(Googlebot|Bingbot|YandexBot)`
    * `nil` - nothing could be proven; the pattern is always tested

  All those literals go into one trie. `candidates/2` walks the subject
  string through it and returns only the patterns whose requirement is
  satisfied, in their original order, so `find/2` preserves exactly the
  first-match-wins semantics of a full linear scan.

  ## Correctness

  The index may only ever *narrow* the set of patterns tested; it must never
  exclude a pattern that could match. Every rule below is therefore
  conservative: anything that cannot be proven yields `nil`, which falls
  back to always testing that pattern. Specifically, a literal run is broken
  by anything optional or variable (quantifiers, wildcards, character
  classes), group contents are only mined when the group is mandatory, and
  lookarounds are never mined at all.
  """

  # A single required literal has to be distinctive to be worth indexing;
  # a one or two character string appears in almost every user agent. The
  # members of an "any of" set can be shorter, since needing one of several
  # specific names is already a strong filter.
  @min_all_length 4
  @min_any_length 3

  # Characters that are only escaped to strip their regex meaning, so the
  # escaped form stands for the literal character.
  @escaped_literals ~c".\\+*?()[]{}|^$/-"

  @enforce_keys [:patterns, :always, :trie]
  defstruct [:patterns, :always, :trie]

  @type requirement :: {:all, binary()} | {:any, [binary()]} | nil

  @type t :: %__MODULE__{
          patterns: tuple(),
          always: [non_neg_integer()],
          trie: map()
        }

  @doc """
  Builds an index from an ordered list of pattern groups.
  """
  @spec build([keyword()]) :: t()
  def build(groups) do
    {always, by_literal} =
      groups
      |> Enum.with_index()
      |> Enum.reduce({[], %{}}, fn {group, index}, acc ->
        group
        |> Keyword.fetch!(:regex)
        |> Regex.source()
        |> requirement()
        |> add_to_index(index, acc)
      end)

    %__MODULE__{
      patterns: List.to_tuple(groups),
      always: Enum.reverse(always),
      trie: Enum.reduce(by_literal, %{}, fn {literal, indices}, trie -> insert(trie, literal, indices) end)
    }
  end

  defp add_to_index(nil, index, {always, by_literal}), do: {[index | always], by_literal}

  defp add_to_index({:all, literal}, index, {always, by_literal}),
    do: {always, Map.update(by_literal, literal, [index], &[index | &1])}

  defp add_to_index({:any, literals}, index, {always, by_literal}) do
    by_literal =
      Enum.reduce(literals, by_literal, fn literal, acc ->
        Map.update(acc, literal, [index], &[index | &1])
      end)

    {always, by_literal}
  end

  defp insert(trie, <<>>, indices), do: Map.update(trie, :terminal, indices, &(indices ++ &1))

  defp insert(trie, <<byte, rest::binary>>, indices),
    do: Map.put(trie, byte, insert(Map.get(trie, byte, %{}), rest, indices))

  @doc """
  Returns `{group, match}` for the first pattern that matches `string`, or
  `nil`. Equivalent to scanning the whole pattern list in order.
  """
  @spec find(t(), binary()) :: {keyword(), [binary()]} | nil
  def find(%__MODULE__{patterns: patterns} = index, string) do
    index
    |> candidates(string)
    |> Enum.find_value(fn position ->
      group = elem(patterns, position)
      regex = Keyword.fetch!(group, :regex)

      case Regex.run(regex, string) do
        nil -> nil
        match -> {group, match}
      end
    end)
  end

  @doc """
  Returns the positions of the patterns whose requirement `string` satisfies,
  in the pattern list's original order. A superset of the patterns that
  actually match.
  """
  @spec candidates(t(), binary()) :: [non_neg_integer()]
  def candidates(%__MODULE__{always: always}, <<>>), do: always

  def candidates(%__MODULE__{always: always, trie: trie}, string) do
    string
    |> from_each_offset(trie, byte_size(string), 0, always)
    |> Enum.sort()
    |> Enum.dedup()
  end

  # Starting a walk at every offset (rather than consuming each match and
  # carrying on after it) is what makes overlapping literals safe: a
  # literal starting inside another one is still found. Offsets are walked
  # by index rather than by taking sub-binaries, which would allocate one
  # per position.
  defp from_each_offset(_string, _trie, size, offset, acc) when offset >= size, do: acc

  defp from_each_offset(string, trie, size, offset, acc) do
    from_each_offset(string, trie, size, offset + 1, walk(trie, string, offset, size, acc))
  end

  defp walk(node, string, position, size, acc) do
    acc = collect(Map.get(node, :terminal), acc)

    if position < size do
      case Map.get(node, :binary.at(string, position)) do
        nil -> acc
        child -> walk(child, string, position + 1, size, acc)
      end
    else
      acc
    end
  end

  defp collect(nil, acc), do: acc
  defp collect(indices, acc), do: indices ++ acc

  @doc """
  Derives the requirement a string must satisfy for `source` (a regex
  source, as returned by `Regex.source/1`) to have any chance of matching.

  Returns `nil` when nothing can be proven.

  ## Examples

      iex> UAParser.Index.requirement("Chrome/(\\\\d+)\\\\.(\\\\d+)")
      {:all, "Chrome/"}

      iex> UAParser.Index.requirement("(Googlebot|Bingbot)/(\\\\d+)")
      {:any, ["Googlebot", "Bingbot"]}

      iex> UAParser.Index.requirement("(\\\\d+)|(\\\\w+)")
      nil

  """
  @spec requirement(binary()) :: requirement()
  def requirement(source) do
    case scan(source, <<>>, <<>>, []) do
      :unprovable ->
        nil

      {best, any_sets} ->
        [{:all, best} | Enum.map(any_sets, &{:any, &1})]
        |> Enum.filter(&viable?/1)
        |> Enum.max_by(&selectivity/1, fn -> nil end)
    end
  end

  defp viable?({:all, literal}), do: byte_size(literal) >= @min_all_length
  defp viable?({:any, []}), do: false
  defp viable?({:any, literals}), do: Enum.all?(literals, &(byte_size(&1) >= @min_any_length))

  # How good a filter this requirement is, approximated by the shortest
  # string we would be searching for: an "any of" set is only as selective
  # as its weakest member.
  defp selectivity({:all, literal}), do: byte_size(literal) * 2
  defp selectivity({:any, literals}), do: literals |> Enum.map(&byte_size/1) |> Enum.min()

  # scan/4 threads the remaining source, the literal run being built, the
  # longest run seen so far, and any "one of these" sets harvested from
  # mandatory alternations.
  defp scan(<<>>, run, best, anys), do: {longer(run, best), anys}

  # Alternation out here splits the whole pattern, so a run collected before
  # it is not required by the other branches.
  defp scan(<<"|", _rest::binary>>, _run, _best, _anys), do: :unprovable

  defp scan(<<"\\", escaped, rest::binary>>, run, best, anys) do
    if escaped in @escaped_literals do
      take_literal(<<escaped>>, rest, run, best, anys)
    else
      scan(rest, <<>>, longer(run, best), anys)
    end
  end

  defp scan(<<"[", rest::binary>>, run, best, anys), do: scan(skip_class(rest), <<>>, longer(run, best), anys)

  defp scan(<<"(?:", rest::binary>>, run, best, anys), do: scan_group(rest, run, best, anys)

  # Lookarounds and named groups: never mined, whatever follows them.
  defp scan(<<"(?", _rest::binary>> = source, run, best, anys) do
    <<"(", rest::binary>> = source
    {_content, after_close} = group_span(rest)
    scan(skip_quantifier(after_close), <<>>, longer(run, best), anys)
  end

  defp scan(<<"(", rest::binary>>, run, best, anys), do: scan_group(rest, run, best, anys)

  defp scan(<<".", rest::binary>>, run, best, anys), do: scan(rest, <<>>, longer(run, best), anys)

  defp scan(<<anchor, rest::binary>>, run, best, anys) when anchor in [?^, ?$], do: scan(rest, run, best, anys)

  defp scan(<<quantifier, rest::binary>>, run, best, anys) when quantifier in [?*, ?+, ?\?] do
    scan(skip_quantifier(<<quantifier, rest::binary>>), <<>>, longer(run, best), anys)
  end

  defp scan(<<"{", rest::binary>>, run, best, anys), do: scan(skip_to_brace(rest), <<>>, longer(run, best), anys)

  defp scan(<<char, rest::binary>>, run, best, anys), do: take_literal(<<char>>, rest, run, best, anys)

  # A character followed by a quantifier may repeat or vanish, so it cannot
  # extend a contiguous run - the run ends before it and restarts after.
  defp take_literal(_char, <<quantifier, _rest::binary>> = source, run, best, anys)
       when quantifier in [?*, ?+, ?\?, ?{] do
    scan(skip_quantifier(source), <<>>, longer(run, best), anys)
  end

  defp take_literal(char, rest, run, best, anys), do: scan(rest, run <> char, best, anys)

  defp scan_group(rest, run, best, anys) do
    {content, after_close} = group_span(rest)
    after_group = skip_quantifier(after_close)
    flushed = longer(run, best)

    # Only a group that appears exactly once is mined. A quantified one may
    # vanish or repeat, and reasoning about where its content lands is not
    # worth the risk of getting it wrong.
    if quantified?(after_close) do
      scan(after_group, <<>>, flushed, anys)
    else
      case branches(content) do
        # A literal from inside a group is never joined to the text around
        # it - we cannot prove where inside the group it sits - so it only
        # competes as a candidate of its own.
        {:one, literal} -> scan(after_group, <<>>, longer(flushed, literal), anys)
        {:any, literals} -> scan(after_group, <<>>, flushed, [literals | anys])
        :unprovable -> scan(after_group, <<>>, flushed, anys)
      end
    end
  end

  defp quantified?(<<quantifier, _rest::binary>>) when quantifier in [?*, ?+, ?\?, ?{], do: true
  defp quantified?(_after_close), do: false

  # Splits a group's content on its top level `|` and derives a literal for
  # each branch. Every branch must yield one, otherwise a string could match
  # through the branch that did not.
  defp branches(content) do
    case split_alternatives(content, 0, <<>>, []) do
      [_only_one] -> single_branch(content)
      alternatives -> any_branch(alternatives)
    end
  end

  defp single_branch(content) do
    case scan(content, <<>>, <<>>, []) do
      :unprovable -> :unprovable
      {best, _anys} -> {:one, best}
    end
  end

  defp any_branch(alternatives) do
    literals = Enum.reduce_while(alternatives, [], &branch_literal/2)

    case literals do
      :unprovable -> :unprovable
      literals -> {:any, literals |> Enum.reverse() |> Enum.uniq()}
    end
  end

  defp branch_literal(alternative, acc) do
    case scan(alternative, <<>>, <<>>, []) do
      {best, _anys} when best != <<>> -> {:cont, [best | acc]}
      _unprovable -> {:halt, :unprovable}
    end
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

  defp longer(a, b) when byte_size(a) >= byte_size(b), do: a
  defp longer(_a, b), do: b
end
