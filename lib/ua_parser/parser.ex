defmodule UAParser.Parser do
  @moduledoc """
  Handle parsing the user-agent string.

  Each of browser/OS/device is resolved in two layers: `UAParser.TreePath`
  is tried first - a fast, regex-free shape match - and `UAParser.RegexPath`
  is the fallback for whatever it doesn't recognise.
  """

  alias UAParser.{RegexPath, Storage, TreePath}

  @doc """
  Parses `user_agent` against the bundled patterns, fetching the patterns
  and their indexes from `UAParser.Storage` in a single lookup.
  """
  def parse(user_agent) do
    {patterns, indexes} = Storage.get()
    run(user_agent, patterns, indexes)
  end

  @doc """
  Parse a user-agent string given a set of patterns.

  When the patterns are the ones held by `UAParser.Storage`, the indexes
  built at load time are used to skip regexes that cannot match. Any other
  pattern set is scanned linearly. Both paths pick the same pattern: the
  first one in the list whose regex matches.
  """
  def parse(patterns, user_agent), do: run(user_agent, patterns, indexes_for(patterns))

  defp run(user_agent, {ua_patterns, os_patterns, device_patterns}, {ua_index, os_index, device_index}) do
    user_agent
    |> sanitize()
    |> parse_user_agent(ua_patterns, ua_index)
    |> parse_device(device_patterns, device_index)
    |> parse_os(os_patterns, os_index)
  end

  defp indexes_for(patterns) do
    case Storage.indexes_for(patterns) do
      nil -> {nil, nil, nil}
      indexes -> indexes
    end
  end

  defp parse_user_agent(user_agent, patterns, index) do
    ua =
      try_tree_path(index, fn -> TreePath.browser(user_agent) end, fn -> RegexPath.ua(patterns, index, user_agent) end)

    {user_agent, ua}
  end

  defp parse_device({user_agent, acc}, patterns, index) do
    device =
      try_tree_path(
        index,
        fn -> TreePath.device(user_agent) end,
        fn -> RegexPath.device(patterns, index, user_agent) end
      )

    {user_agent, Map.put(acc, :device, device)}
  end

  defp parse_os({user_agent, acc}, patterns, index) do
    os = try_tree_path(index, fn -> TreePath.os(user_agent) end, fn -> RegexPath.os(patterns, index, user_agent) end)
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
