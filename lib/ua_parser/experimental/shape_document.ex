defmodule UAParser.Experimental.ShapeDocument do
  @moduledoc """
  EXPERIMENTAL - shared compile-time helpers for reading a section of
  `priv/ua_shapes.yml`'s yamerl-parsed keyword lists.

  `UAParser.Experimental.TreeMatcher` (the `user_agent` section) and
  `UAParser.Experimental.OSMatcher` (the `os` section) read different
  parts of the same document - they don't interact, but they need the
  same handful of "pull this key out as a string/list/map" conversions,
  so that part is shared instead of duplicated.
  """

  @doc "Reads `path` and returns the keyword list under `section` (an atom)."
  @spec section(binary(), atom()) :: keyword()
  def section(path, section) do
    path
    |> String.to_charlist()
    |> :yamerl_constr.file([])
    |> hd()
    |> List.keyfind(Atom.to_charlist(section), 0)
    |> elem(1)
  end

  @spec fetch_str(keyword(), charlist()) :: binary() | nil
  def fetch_str(kw, key) do
    case List.keyfind(kw, key, 0) do
      {_key, value} -> to_string(value)
      nil -> nil
    end
  end

  @spec fetch_list(keyword(), charlist()) :: [binary()]
  def fetch_list(kw, key) do
    case List.keyfind(kw, key, 0) do
      {_key, values} -> Enum.map(values, &to_string/1)
      nil -> []
    end
  end

  @spec fetch_int(keyword(), charlist(), integer()) :: integer()
  def fetch_int(kw, key, default) do
    case List.keyfind(kw, key, 0) do
      {_key, value} -> value
      nil -> default
    end
  end

  @spec fetch_map(keyword(), charlist()) :: %{optional(binary()) => binary()} | nil
  def fetch_map(kw, key) do
    case List.keyfind(kw, key, 0) do
      {_key, pairs} -> Map.new(pairs, fn {k, v} -> {to_string(k), to_string(v)} end)
      nil -> nil
    end
  end
end
