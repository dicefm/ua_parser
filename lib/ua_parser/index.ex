defmodule UAParser.Index do
  @moduledoc false

  # An index over one pattern list that skips regexes that cannot match.
  #
  # Each pattern has a requirement mined from its regex source at compile
  # time (see `UAParser.Index.Requirements`): a literal the string must
  # contain, one of several literals, or nil when nothing could be proven.
  # All literals are compiled into one `:binary.compile_pattern/1` pattern,
  # so a single scan of the string finds which patterns can possibly match.
  # `candidates/2` returns those, in list order, so searching them finds the
  # same pattern a full linear scan would.

  alias UAParser.Index.RequirementMiner

  @enforce_keys [:patterns, :always, :pattern, :by_literal]
  defstruct [:patterns, :always, :pattern, :by_literal]

  @type t :: %__MODULE__{
          patterns: tuple(),
          always: [non_neg_integer()],
          pattern: :binary.cp(),
          by_literal: %{binary() => [non_neg_integer()]}
        }

  @doc """
  Builds an index from an ordered list of pattern groups and the
  requirements mined from them, in the same order.
  """
  @spec build([keyword()], [RequirementMiner.requirement()]) :: t()
  def build(groups, requirements) do
    {always, by_literal} =
      requirements
      |> Enum.with_index()
      |> Enum.reduce({[], %{}}, &add_to_index/2)

    %__MODULE__{
      patterns: List.to_tuple(groups),
      always: Enum.reverse(always),
      pattern: by_literal |> Map.keys() |> :binary.compile_pattern(),
      by_literal: Map.new(by_literal, fn {literal, indices} -> {literal, indices ++ prefixes(literal, by_literal)} end)
    }
  end

  defp add_to_index({nil, index}, {always, by_literal}), do: {[index | always], by_literal}

  defp add_to_index({{:all, literal}, index}, {always, by_literal}),
    do: {always, put_literal(by_literal, literal, index)}

  defp add_to_index({{:any, literals}, index}, {always, by_literal}),
    do: {always, Enum.reduce(literals, by_literal, &put_literal(&2, &1, index))}

  defp put_literal(by_literal, literal, index), do: Map.update(by_literal, literal, [index], &[index | &1])

  # When several literals start at the same position, `:binary.match/3`
  # only reports the longest. A shorter one starting there is a prefix of
  # it, so each literal also carries the patterns of its prefixes.
  defp prefixes(literal, by_literal) do
    for {other, indices} <- by_literal,
        other != literal,
        String.starts_with?(literal, other),
        index <- indices,
        do: index
  end

  @doc """
  Returns the pattern groups whose requirement `string` satisfies, in list
  order. A superset of the groups that match.
  """
  @spec candidates(t(), binary()) :: [keyword()]
  def candidates(%__MODULE__{patterns: patterns, always: always, pattern: pattern, by_literal: by_literal}, string) do
    # Literals are mined lowercased, so the string is folded to match.
    folded = String.downcase(string)

    folded
    |> scan(pattern, by_literal, 0, byte_size(folded), always)
    |> :lists.usort()
    |> Enum.map(&elem(patterns, &1))
  end

  # Restarting one byte after each match start, rather than after its end,
  # finds literals that start inside a previous match.
  defp scan(_string, _pattern, _by_literal, position, size, acc) when position >= size, do: acc

  defp scan(string, pattern, by_literal, position, size, acc) do
    case :binary.match(string, pattern, scope: {position, size - position}) do
      :nomatch ->
        acc

      {start, length} ->
        literal = binary_part(string, start, length)
        scan(string, pattern, by_literal, start + 1, size, Map.fetch!(by_literal, literal) ++ acc)
    end
  end
end
