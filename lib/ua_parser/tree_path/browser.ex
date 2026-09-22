defmodule UAParser.TreePath.Browser do
  @moduledoc """
  Matches the `user_agent` section of `priv/ua_shapes.yml` - browser
  identification for the high-volume shapes (Chrome, Firefox and Safari
  families, and the in-app browsers that brand them). See
  `priv/ua_shapes.yml` for the branch fields, and `UAParser.TreePath`'s
  moduledoc for why this exists.

  At compile time, generates one `try_branch/2` clause per branch; a
  miss recurses to the next. No `Regex.run` anywhere in the matching
  path.
  """

  alias UAParser.{TreePath, UA}
  alias UAParser.TreePath.Document

  @shapes_path Path.expand("../../../priv/ua_shapes.yml", __DIR__)
  @external_resource @shapes_path

  document = Document.section(@shapes_path, :user_agent)
  fetch_str = &Document.fetch_str/2
  fetch_list = &Document.fetch_list/2
  fetch_int = &Document.fetch_int/3

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
        none: fetch_list.(branch, ~c"none"),
        version_after: fetch_str.(branch, ~c"version_after"),
        min_parts: fetch_int.(branch, ~c"version_min_parts", 0)
      }
    end)

  @exclude_words exclude_words
  @branches branches
  @all_needles branches
               |> Enum.flat_map(&[[&1.version_after], &1.all, &1.any_of, &1.none])
               |> List.flatten()
               |> Enum.uniq()

  for {branch, index} <- Enum.with_index(branches) do
    defp try_branch(unquote(index), string) do
      case check_branch(string, unquote(Macro.escape(branch))) do
        {:ok, version} -> %UA{family: unquote(branch.family), version: TreePath.version(version)}
        :fail -> try_branch(unquote(index + 1), string)
      end
    end
  end

  # No branch matched.
  defp try_branch(_index, _string), do: :no_match

  @doc "Compiles this module's patterns into `:persistent_term`. Call once, at boot."
  @spec warm() :: :ok
  def warm do
    Document.warm(__MODULE__, @all_needles)
    Document.warm_group(__MODULE__, @exclude_words)

    for %{any_of: any_of, none: none} <- @branches do
      if any_of != [], do: Document.warm_group(__MODULE__, any_of)
      if none != [], do: Document.warm_group(__MODULE__, none)
    end

    :ok
  end

  @doc """
  Matches `string`, returning a `UAParser.UA` (with `os`/`device` unset -
  `UAParser.Parser` fills those in separately) or `:no_match`.
  """
  @spec match(binary()) :: UA.t() | :no_match
  def match(string) do
    if hit?(string, @exclude_words) do
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
  # :binary.match calls on `all`/`any_of` first. `any_of`/`none` are each
  # checked with one combined-pattern match (compiled by `warm/0`) rather
  # than one `:binary.match` per needle - some `none` lists run to several
  # dozen entries.
  defp check_branch(string, %{all: all, any_of: any_of, none: none, version_after: marker, min_parts: min_parts}) do
    with {pos, len} <- :binary.match(string, Document.compiled(__MODULE__, marker)),
         true <- Enum.all?(all, &hit?(string, &1)),
         true <- any_of == [] or hit?(string, any_of),
         true <- none == [] or not hit?(string, none),
         version <- extract_version(string, pos + len),
         true <- version_parts(version) >= min_parts do
      {:ok, version}
    else
      _other -> :fail
    end
  end

  defp hit?(string, needle), do: Document.hit?(__MODULE__, string, needle)

  defp extract_version(string, start) do
    version_run(binary_part(string, start, byte_size(string) - start), <<>>)
  end

  defp version_run(<<c, rest::binary>>, acc) when c in ?0..?9 or c == ?., do: version_run(rest, <<acc::binary, c>>)
  defp version_run(_rest, acc), do: acc

  defp version_parts(<<>>), do: 0
  defp version_parts(version), do: version |> String.split(".") |> length()
end
