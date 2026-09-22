defmodule UAParser.Experimental.TreeMatcher do
  @moduledoc """
  EXPERIMENTAL - not part of the public API, not wired into `UAParser.parse/1`.

  A prototype for a specific question: could a hand-authored document
  describing UA shapes (`priv/ua_shapes.yml`), compiled into a tree of
  recursive Elixir functions, match `UAParser.Index` + `Regex.run`'s
  results for the small set of high-volume, regular templates (Chrome
  family, Firefox, Safari family) that make up the bulk of real traffic -
  with no regex engine involved at all?

  `priv/ua_shapes.yml` lists browser "branches" in priority order (most
  specific first). Each branch declares which substrings must all be
  present (`all`), which set at least one must come from (`any_of`), and
  where to find the version (`version_after`, with an optional
  `version_min_parts` - a "reduced" UA like `Chrome/125` isn't claimed by
  patterns.yml's real Chrome pattern either, since it requires a full
  X.Y.Z.W version, so this tree doesn't claim it either). A top-level
  `exclude_if_any` short-circuits to `:no_match` for known spoofing risks
  (bots that embed a real browser's tokens for compatibility) - listed in
  both common capitalizations rather than folding the whole subject
  string's case, which would allocate a full copy on every call.

  At compile time, this module reads that document and generates one
  `try_branch/2` function clause per branch; a miss recurses to the next
  branch by calling the next clause - the literal "generate functions to
  be called recursively" idea. `check_branch/2` (shared, not generated) is
  what plain `:binary.match/2` calls do the actual checking.

  See `bench/tree_vs_regex.exs` for the head-to-head benchmark and
  correctness check against `UAParser.parse/1`.
  """

  alias UAParser.Experimental.ShapeDocument

  @shapes_path Path.expand("../../../priv/ua_shapes.yml", __DIR__)
  @external_resource @shapes_path

  document = ShapeDocument.section(@shapes_path, :user_agent)
  fetch_str = &ShapeDocument.fetch_str/2
  fetch_list = &ShapeDocument.fetch_list/2
  fetch_int = &ShapeDocument.fetch_int/3

  exclude_words = fetch_list.(document, ~c"exclude_if_any")

  branches =
    document
    |> List.keyfind(~c"branches", 0)
    |> elem(1)
    |> Enum.map(fn branch ->
      %{
        family: fetch_str.(branch, ~c"family"),
        all: fetch_list.(branch, ~c"all"),
        any_of: fetch_list.(branch, ~c"any_of"),
        version_after: fetch_str.(branch, ~c"version_after"),
        min_parts: fetch_int.(branch, ~c"version_min_parts", 0)
      }
    end)

  @exclude_words exclude_words

  for {branch, index} <- Enum.with_index(branches) do
    defp try_branch(unquote(index), string) do
      case check_branch(string, unquote(Macro.escape(branch))) do
        {:ok, version} -> {unquote(branch.family), version}
        :fail -> try_branch(unquote(index + 1), string)
      end
    end
  end

  # No branch matched.
  defp try_branch(_index, _string), do: :no_match

  @doc """
  Matches `string` against the shape document, returning `{family, version}`
  or `:no_match`. `version` is the raw digit-and-dot run found after the
  matching marker (e.g. `"128.0.0.0"`), not split into major/minor/patch -
  this prototype only needs to compare family + version text against
  `UAParser.parse/1`, not build a full `UAParser.UA` struct.
  """
  @spec match(binary()) :: {binary(), binary()} | :no_match
  def match(string) do
    if :binary.match(string, @exclude_words) != :nomatch do
      :no_match
    else
      try_branch(0, string)
    end
  end

  # `version_after` is checked first, and only once, whatever else the
  # branch requires: it's the branch's primary, most-discriminating
  # condition, and most branches fail here for a given string (their
  # marker just isn't in it) - so this is the fast path for the common
  # case of "wrong branch, try the next one" without spending any extra
  # :binary.match calls on `all`/`any_of` first.
  defp check_branch(string, %{all: all, any_of: any_of, version_after: marker, min_parts: min_parts}) do
    with {pos, len} <- :binary.match(string, marker),
         true <- Enum.all?(all, &contains?(string, &1)),
         true <- any_of == [] or Enum.any?(any_of, &contains?(string, &1)),
         version <- extract_version(string, pos + len),
         true <- version_parts(version) >= min_parts do
      {:ok, version}
    else
      _other -> :fail
    end
  end

  defp contains?(string, substring), do: :binary.match(string, substring) != :nomatch

  defp extract_version(string, start) do
    version_run(binary_part(string, start, byte_size(string) - start), <<>>)
  end

  defp version_run(<<c, rest::binary>>, acc) when c in ?0..?9 or c == ?., do: version_run(rest, <<acc::binary, c>>)
  defp version_run(_rest, acc), do: acc

  defp version_parts(<<>>), do: 0
  defp version_parts(version), do: version |> String.split(".") |> length()
end
