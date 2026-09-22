defmodule UAParser.TreePath.OS do
  @moduledoc """
  Matches the `os` section of `priv/ua_shapes.yml` - see its comments
  for the branch fields, and `UAParser.TreePath.Browser`'s moduledoc for
  the shared compile-time design.
  """

  alias UAParser.{OperatingSystem, TreePath}
  alias UAParser.TreePath.Document

  @shapes_path Path.expand("../../../priv/ua_shapes.yml", __DIR__)
  @external_resource @shapes_path

  document = Document.section(@shapes_path, :os)
  fetch_str! = &Document.fetch_str!/2
  fetch_map = &Document.fetch_map/2

  branches =
    document
    |> Document.branches()
    |> Enum.map(fn branch ->
      %{
        family: fetch_str!.(branch, ~c"family"),
        version_after: fetch_str!.(branch, ~c"version_after"),
        version_map: fetch_map.(branch, ~c"version_map")
      }
    end)

  @all_needles branches |> Enum.map(& &1.version_after) |> Enum.uniq()

  for {branch, index} <- Enum.with_index(branches) do
    defp try_branch(unquote(index), string) do
      case check_branch(string, unquote(Macro.escape(branch))) do
        {:ok, version} -> %OperatingSystem{family: unquote(branch.family), version: TreePath.version(version)}
        :fail -> try_branch(unquote(index + 1), string)
      end
    end
  end

  defp try_branch(_index, _string), do: :no_match

  @doc "Compiles this module's patterns into `:persistent_term`. Call once, at boot."
  @spec warm() :: :ok
  def warm, do: Document.warm(__MODULE__, @all_needles)

  @doc "Matches `string`, returning a `UAParser.OperatingSystem` or `:no_match`."
  @spec match(binary()) :: OperatingSystem.t() | :no_match
  def match(string), do: try_branch(0, string)

  defp check_branch(string, %{version_after: marker, version_map: nil}) do
    case :binary.match(string, Document.compiled(__MODULE__, marker)) do
      {pos, len} -> {:ok, extract_version(string, pos + len)}
      :nomatch -> :fail
    end
  end

  defp check_branch(string, %{version_after: marker, version_map: version_map}) do
    with {pos, len} <- :binary.match(string, Document.compiled(__MODULE__, marker)),
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
