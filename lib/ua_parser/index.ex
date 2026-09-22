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

  So each pattern is built from a *requirement* - a literal that any
  matching string must contain, or an "any of" set from an alternation -
  derived from its regex source by `UAParser.RequirementMiner`. That
  derivation happens once, at compile time (see `UAParser.Requirements`);
  this module only ever consumes its output, so the parse hot path never
  runs a regex-source scanner.

  All those literals go into one trie. `candidates/2` walks the subject
  string through it and returns only the patterns whose requirement is
  satisfied, in their original order, so `find/2` preserves exactly the
  first-match-wins semantics of a full linear scan.

  Literals are matched case-insensitively: they are folded by
  `RequirementMiner` when mined, and the subject is folded once per call
  here. That costs one pass over the string and makes requirements
  slightly less selective, but it lets a class like `[Bb]` pin a
  character, which is worth far more than it costs.
  """

  alias UAParser.RequirementMiner

  @enforce_keys [:patterns, :always, :trie]
  defstruct [:patterns, :always, :trie]

  @type t :: %__MODULE__{
          patterns: tuple(),
          always: [non_neg_integer()],
          trie: map()
        }

  @doc """
  Builds an index from an ordered list of pattern groups and the
  requirements mined from them, in the same order (see
  `UAParser.Requirements`).
  """
  @spec build([keyword()], [RequirementMiner.requirement()]) :: t()
  def build(groups, requirements) do
    {always, by_literal} =
      groups
      |> Enum.zip(requirements)
      |> Enum.with_index()
      |> Enum.reduce({[], %{}}, fn {{_group, requirement}, index}, acc -> add_to_index(requirement, index, acc) end)

    %__MODULE__{
      patterns: List.to_tuple(groups),
      always: Enum.reverse(always),
      trie:
        Enum.reduce(by_literal, %{}, fn {literal, indices}, trie ->
          insert(trie, literal, indices)
        end)
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
    folded = String.downcase(string)

    folded
    |> from_each_offset(trie, byte_size(folded), 0, always)
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
end
