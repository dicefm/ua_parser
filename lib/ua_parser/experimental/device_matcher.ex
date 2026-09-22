defmodule UAParser.Experimental.DeviceMatcher do
  @moduledoc """
  EXPERIMENTAL - not part of the public API, not wired into `UAParser.parse/1`.

  Same idea as `UAParser.Experimental.TreeMatcher`/`OSMatcher`, applied to
  the device half of parsing: the `device` section of `priv/ua_shapes.yml`
  lists device shapes in priority order, compiled at compile time into a
  tree of recursive Elixir functions, no `Regex.run` anywhere.

  Device is the least regular of the three pattern lists (633 patterns,
  mostly one-off vendor/model codes), so only a couple of shapes are
  covered - see the comments in `priv/ua_shapes.yml`'s `device` section
  for why "Mac" needed real traffic to get right, not just the regex
  source.

  Device shapes don't carry a version - the result is a fixed
  `{family, brand, model}` once a branch's conditions are met.
  """

  alias UAParser.Experimental.ShapeDocument

  @shapes_path Path.expand("../../../priv/ua_shapes.yml", __DIR__)
  @external_resource @shapes_path

  document = ShapeDocument.section(@shapes_path, :device)
  fetch_str = &ShapeDocument.fetch_str/2
  fetch_list = &ShapeDocument.fetch_list/2

  branches =
    document
    |> List.keyfind(~c"branches", 0)
    |> elem(1)
    |> Enum.map(fn branch ->
      %{
        family: fetch_str.(branch, ~c"family"),
        brand: fetch_str.(branch, ~c"brand"),
        model: fetch_str.(branch, ~c"model"),
        marker: fetch_str.(branch, ~c"marker"),
        any_of: fetch_list.(branch, ~c"any_of")
      }
    end)

  @all_needles branches
               |> Enum.flat_map(&[[&1.marker], &1.any_of])
               |> List.flatten()
               |> Enum.reject(&is_nil/1)
               |> Enum.uniq()

  for {branch, index} <- Enum.with_index(branches) do
    defp try_branch(unquote(index), string) do
      if check_branch?(string, unquote(Macro.escape(branch))) do
        {unquote(branch.family), unquote(branch.brand), unquote(branch.model)}
      else
        try_branch(unquote(index + 1), string)
      end
    end
  end

  defp try_branch(_index, _string), do: :no_match

  @doc """
  Compiles every needle this module searches for via
  `:binary.compile_pattern/1` and stores the results in `:persistent_term`,
  keyed by the literal string. Call once (e.g. from `UAParser.Application`)
  before `match/1`. See `UAParser.Experimental.TreeMatcher.warm/0`.
  """
  @spec warm() :: :ok
  def warm do
    for needle <- @all_needles, do: :persistent_term.put({__MODULE__, needle}, :binary.compile_pattern(needle))
    :ok
  end

  @doc """
  Matches `string` against the device shape document, returning
  `{family, brand, model}` or `:no_match`.
  """
  @spec match(binary()) :: {binary(), binary(), binary()} | :no_match
  def match(string), do: try_branch(0, string)

  defp check_branch?(string, %{marker: nil, any_of: any_of}), do: Enum.any?(any_of, &hit?(string, &1))
  defp check_branch?(string, %{marker: marker}), do: hit?(string, marker)

  defp hit?(string, needle), do: :binary.match(string, compiled(needle)) != :nomatch

  defp compiled(needle), do: :persistent_term.get({__MODULE__, needle})
end
