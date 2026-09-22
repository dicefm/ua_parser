defmodule UAParser.Experimental.OSMatcher do
  @moduledoc """
  EXPERIMENTAL - not part of the public API, not wired into `UAParser.parse/1`.

  Same idea as `UAParser.Experimental.TreeMatcher`, applied to the OS half
  of parsing instead of the browser half: the `os` section of
  `priv/ua_shapes.yml` lists OS shapes in priority order, compiled at
  compile time into a tree of recursive Elixir functions, no `Regex.run`
  anywhere.

  This exists because `UAParser.Index` already treats user-agent, OS and
  device as three independent pattern lists - a single tree trying to
  cover all three at once would be solving three different problems in
  one place. Splitting them the same way the real system does keeps each
  tree only needing to know about shapes in its own domain.

  A branch's version can come two ways:

    * extracted directly (`version_after`) - most OSes report their own
      version in the string, e.g. `Android 13`.
    * looked up (`version_map`) - Windows NT build numbers aren't the
      marketing version at all (`Windows NT 6.1` is "Windows 7"), so
      patterns.yml hardcodes that mapping, and this does too.

  See `UAParser.Experimental.TreeMatcher`'s moduledoc for the rest of the
  design (why compile time, why recursion, why no regex).
  """

  alias UAParser.Experimental.ShapeDocument

  @shapes_path Path.expand("../../../priv/ua_shapes.yml", __DIR__)
  @external_resource @shapes_path

  document = ShapeDocument.section(@shapes_path, :os)
  fetch_str = &ShapeDocument.fetch_str/2
  fetch_map = &ShapeDocument.fetch_map/2

  branches =
    document
    |> List.keyfind(~c"branches", 0)
    |> elem(1)
    |> Enum.map(fn branch ->
      %{
        family: fetch_str.(branch, ~c"family"),
        version_after: fetch_str.(branch, ~c"version_after"),
        version_map: fetch_map.(branch, ~c"version_map")
      }
    end)

  for {branch, index} <- Enum.with_index(branches) do
    defp try_branch(unquote(index), string) do
      case check_branch(string, unquote(Macro.escape(branch))) do
        {:ok, version} -> {unquote(branch.family), version}
        :fail -> try_branch(unquote(index + 1), string)
      end
    end
  end

  defp try_branch(_index, _string), do: :no_match

  @doc """
  Matches `string` against the OS shape document, returning
  `{family, version}` or `:no_match`.
  """
  @spec match(binary()) :: {binary(), binary()} | :no_match
  def match(string), do: try_branch(0, string)

  defp check_branch(string, %{version_after: marker, version_map: nil}) do
    case :binary.match(string, marker) do
      {pos, len} -> {:ok, extract_version(string, pos + len)}
      :nomatch -> :fail
    end
  end

  defp check_branch(string, %{version_after: marker, version_map: version_map}) do
    with {pos, len} <- :binary.match(string, marker),
         raw <- extract_version(string, pos + len),
         {:ok, mapped} <- Map.fetch(version_map, raw) do
      {:ok, mapped}
    else
      _other -> :fail
    end
  end

  # Most markers are immediately followed by the version. Chrome OS's real
  # pattern is `(CrOS) [a-z0-9_]+ (\d+)\.(\d+)...` - a board-name token
  # (e.g. "x86_64") sits between the marker and the version, so skip up to
  # one non-digit "word" first.
  defp extract_version(string, start) do
    rest = binary_part(string, start, byte_size(string) - start)

    case version_run(rest, <<>>) do
      <<>> -> rest |> skip_word() |> version_run(<<>>)
      version -> version
    end
  end

  defp skip_word(<<" ", rest::binary>>), do: rest
  defp skip_word(<<_char, rest::binary>>), do: skip_word(rest)
  defp skip_word(<<>>), do: <<>>

  defp version_run(<<c, rest::binary>>, acc) when c in ?0..?9, do: version_run(rest, <<acc::binary, c>>)
  defp version_run(<<c, rest::binary>>, acc) when c in [?., ?_], do: version_run(rest, <<acc::binary, ".">>)
  defp version_run(_rest, acc), do: acc
end
