defmodule UAParser.TreePath.Device do
  @moduledoc """
  Matches the `device` section of `priv/ua_shapes.yml` - see its
  comments for the branch fields, and `UAParser.TreePath.Browser`'s
  moduledoc for the shared compile-time design.
  """

  alias UAParser.Device, as: DeviceStruct
  alias UAParser.TreePath.Document

  @shapes_path Path.expand("../../../priv/ua_shapes.yml", __DIR__)
  @external_resource @shapes_path

  document = Document.section(@shapes_path, :device)
  fetch_str = &Document.fetch_str/2
  fetch_list = &Document.fetch_list/2

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
        %DeviceStruct{family: unquote(branch.family), brand: unquote(branch.brand), model: unquote(branch.model)}
      else
        try_branch(unquote(index + 1), string)
      end
    end
  end

  defp try_branch(_index, _string), do: :no_match

  @doc "Compiles this module's patterns into `:persistent_term`. Call once, at boot."
  @spec warm() :: :ok
  def warm, do: Document.warm(__MODULE__, @all_needles)

  @doc "Matches `string`, returning a `UAParser.Device` or `:no_match`."
  @spec match(binary()) :: DeviceStruct.t() | :no_match
  def match(string), do: try_branch(0, string)

  defp check_branch?(string, %{marker: nil, any_of: any_of}), do: Enum.any?(any_of, &hit?(string, &1))
  defp check_branch?(string, %{marker: marker}), do: hit?(string, marker)

  defp hit?(string, needle), do: Document.hit?(__MODULE__, string, needle)
end
