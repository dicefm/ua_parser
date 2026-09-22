defmodule UAParser.TreePath.Document do
  @moduledoc """
  Shared helpers for `UAParser.TreePath.Browser`/`OS`/`Device`: reading a
  section of `priv/ua_shapes.yml`'s yamerl-parsed keyword lists at compile
  time, and compiling+caching `:binary.match/2` patterns at runtime.

  `:binary.compile_pattern/1`'s result is a reference - it cannot be a
  compile-time literal (Elixir rejects embedding it as a module
  attribute), so every needle a matcher searches for is compiled once, at
  boot, by that matcher's `warm/0`, and read back from `:persistent_term`
  on every `match/1` call instead of being recompiled from a raw literal
  each time.
  """

  alias UAParser.Processor

  @doc "Reads `path` and returns the keyword list under `section` (an atom)."
  @spec section(binary(), atom()) :: keyword()
  def section(path, section) do
    path
    |> Processor.load_yaml()
    |> hd()
    |> List.keyfind(Atom.to_charlist(section), 0)
    |> elem(1)
  end

  @spec fetch_str(keyword(), charlist()) :: binary() | nil
  def fetch_str(kw, key), do: fetch(kw, key, nil, &to_string/1)

  @spec fetch_list(keyword(), charlist()) :: [binary()]
  def fetch_list(kw, key), do: fetch(kw, key, [], fn values -> Enum.map(values, &to_string/1) end)

  @spec fetch_int(keyword(), charlist(), integer()) :: integer()
  def fetch_int(kw, key, default), do: fetch(kw, key, default, & &1)

  @spec fetch_map(keyword(), charlist()) :: %{optional(binary()) => binary()} | nil
  def fetch_map(kw, key) do
    fetch(kw, key, nil, fn pairs -> Map.new(pairs, fn {k, v} -> {to_string(k), to_string(v)} end) end)
  end

  defp fetch(kw, key, default, transform) do
    case List.keyfind(kw, key, 0) do
      {_key, value} -> transform.(value)
      nil -> default
    end
  end

  @doc "Compiles each of `needles` individually for `module` and caches it."
  @spec warm(module(), [binary()]) :: :ok
  def warm(module, needles) do
    for needle <- needles, do: :persistent_term.put({module, needle}, :binary.compile_pattern(needle))
    :ok
  end

  @doc "Compiles `needles` as a single combined pattern for `module` and caches it."
  @spec warm_group(module(), [binary()]) :: :ok
  def warm_group(module, needles) do
    :persistent_term.put({module, needles}, :binary.compile_pattern(needles))
    :ok
  end

  @doc "Reads back a pattern compiled by `warm/2` or `warm_group/2`."
  @spec compiled(module(), binary() | [binary()]) :: :binary.cp()
  def compiled(module, needle), do: :persistent_term.get({module, needle})

  @doc "Whether `needle` (compiled by `warm/2` or `warm_group/2`) occurs in `string`."
  @spec hit?(module(), binary(), binary() | [binary()]) :: boolean()
  def hit?(module, string, needle), do: :binary.match(string, compiled(module, needle)) != :nomatch
end
