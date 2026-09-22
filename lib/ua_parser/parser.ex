defmodule UAParser.Parser do
  @moduledoc """
  Handle parsing the user-agent string.

  Each of browser/OS/device is resolved in two layers: `UAParser.TreePath`
  is tried first - a fast, regex-free shape match - and `UAParser.RegexPath`
  is the fallback for whatever it doesn't recognise.
  """

  alias UAParser.{Device, OperatingSystem, RegexPath, Storage, TreePath, UA}

  @domains [:browser, :os, :device]

  @doc "The domains `only` can select in `parse/2`."
  @spec domains() :: [atom()]
  def domains, do: @domains

  @doc """
  Parses `user_agent` against the bundled patterns, resolving only the
  domains in `only` (see `domains/0`). Fetches the patterns and their
  indexes from `UAParser.Storage` in a single lookup. A domain left out
  of `only` comes back as its empty struct, the same as when nothing
  matches.
  """
  @spec parse(binary(), [atom()]) :: UA.t()
  def parse(user_agent, only) when is_list(only) do
    {patterns, indexes} = Storage.get()
    run(user_agent, patterns, indexes, only)
  end

  @doc """
  Parses `user_agent` against a caller-supplied pattern set, resolving
  all domains.

  When `patterns` is the one held by `UAParser.Storage`, the indexes
  built at load time are used to skip regexes that cannot match. Any
  other pattern set is scanned linearly. Both pick the same pattern:
  the first one in the list whose regex matches.
  """
  @spec parse_with_patterns({list(), list(), list()}, binary()) :: UA.t()
  def parse_with_patterns(patterns, user_agent), do: run(user_agent, patterns, indexes_for(patterns), @domains)

  defp run(user_agent, {ua_patterns, os_patterns, device_patterns}, {ua_index, os_index, device_index}, only) do
    user_agent
    |> sanitize()
    |> parse_user_agent(ua_patterns, ua_index, only)
    |> parse_device(device_patterns, device_index, only)
    |> parse_os(os_patterns, os_index, only)
  end

  defp indexes_for(patterns) do
    case Storage.indexes_for(patterns) do
      nil -> {nil, nil, nil}
      indexes -> indexes
    end
  end

  defp parse_user_agent(user_agent, patterns, index, only) do
    ua =
      if :browser in only do
        try_tree_path(index, fn -> TreePath.browser(user_agent) end, fn -> RegexPath.ua(patterns, index, user_agent) end)
      else
        %UA{}
      end

    {user_agent, ua}
  end

  defp parse_device({user_agent, acc}, patterns, index, only) do
    device =
      if :device in only do
        try_tree_path(
          index,
          fn -> TreePath.device(user_agent) end,
          fn -> RegexPath.device(patterns, index, user_agent) end
        )
      else
        %Device{}
      end

    {user_agent, Map.put(acc, :device, device)}
  end

  defp parse_os({user_agent, acc}, patterns, index, only) do
    os =
      if :os in only do
        try_tree_path(index, fn -> TreePath.os(user_agent) end, fn -> RegexPath.os(patterns, index, user_agent) end)
      else
        %OperatingSystem{}
      end

    Map.put(acc, :os, os)
  end

  # TreePath only applies to the bundled patterns (index present - a
  # caller-supplied pattern list gets nil, same as UAParser.Index does),
  # since every shape is grounded in the bundled patterns.yml's specific
  # regexes, not whatever a caller happens to pass in.
  defp try_tree_path(nil, _tree_path, regex_path), do: regex_path.()

  defp try_tree_path(_index, tree_path, regex_path) do
    case tree_path.() do
      :no_match -> regex_path.()
      result -> result
    end
  end

  defp sanitize(user_agent), do: String.trim(user_agent)
end
