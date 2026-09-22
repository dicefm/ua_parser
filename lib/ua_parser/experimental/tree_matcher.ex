defmodule UAParser.Experimental.TreeMatcher do
  @moduledoc """
  EXPERIMENTAL - not part of the public API, not wired into `UAParser.parse/1`.

  A prototype for a specific question: could a hand-authored document
  describing UA shapes (`priv/ua_shapes.yml`), compiled into a tree of
  recursive Elixir functions, beat `UAParser.Index` + `Regex.run` for the
  small set of high-volume, regular templates (Chrome-family, Firefox,
  Safari) that make up the bulk of real traffic - with no regex engine
  involved at all?

  `priv/ua_shapes.yml` lists browser "branches" in priority order (most
  specific first, since Edge/Opera/Samsung Internet UAs also carry a
  `Chrome/` token for compatibility). At compile time, this module reads
  that document and generates one `try_branch/2` function clause per
  branch, each doing a plain `:binary.match/2` for its marker and a
  hand-written digit-run scan for the version - no `Regex.run` anywhere.
  A miss recurses to the next branch by calling the next clause, which is
  the literal "generate functions to be called recursively" idea.

  See `bench/tree_vs_regex.exs` for the head-to-head benchmark and
  correctness check against `UAParser.parse/1`.
  """

  @shapes_path Path.expand("../../../priv/ua_shapes.yml", __DIR__)
  @external_resource @shapes_path

  branches =
    @shapes_path
    |> String.to_charlist()
    |> :yamerl_constr.file([])
    |> hd()
    |> hd()
    |> elem(1)
    |> Enum.map(fn branch ->
      fetch = fn key -> branch |> List.keyfind(key, 0) |> elem(1) |> to_string() end

      confirm =
        case List.keyfind(branch, ~c"confirm", 0),
          do: (
            {_, v} -> to_string(v)
            nil -> nil
          )

      {fetch.(~c"family"), fetch.(~c"marker"), confirm}
    end)

  for {{family, marker, confirm}, index} <- Enum.with_index(branches) do
    defp try_branch(unquote(index), string) do
      case :binary.match(string, unquote(marker)) do
        {pos, len} ->
          if unquote(confirm) == nil or :binary.match(string, unquote(confirm)) != :nomatch do
            {unquote(family), extract_version(string, pos + len)}
          else
            try_branch(unquote(index + 1), string)
          end

        :nomatch ->
          try_branch(unquote(index + 1), string)
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
  def match(string), do: try_branch(0, string)

  defp extract_version(string, start) do
    version_run(binary_part(string, start, byte_size(string) - start), <<>>)
  end

  defp version_run(<<c, rest::binary>>, acc) when c in ?0..?9 or c == ?., do: version_run(rest, <<acc::binary, c>>)
  defp version_run(_rest, acc), do: acc
end
