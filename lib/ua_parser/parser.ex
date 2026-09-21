defmodule UAParser.Parser do
  @moduledoc """
  Handle parsing the user-agent string.
  """

  alias UAParser.{Index, Storage}
  alias UAParser.Parsers.{Device, OperatingSystem, UA}

  @doc """
  Parse a user-agent string given a set of patterns.

  When the patterns are the ones held by `UAParser.Storage`, the indexes
  built at load time are used to skip regexes that cannot match. Any other
  pattern set is scanned linearly. Both paths pick the same pattern: the
  first one in the list whose regex matches.
  """
  def parse({ua_patterns, os_patterns, device_patterns} = patterns, user_agent) do
    {ua_index, os_index, device_index} = indexes_for(patterns)

    user_agent
    |> sanitize
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

  defp find_and_parse(patterns, index, user_agent, module) do
    patterns
    |> search(index, user_agent)
    |> module.parse
  end

  defp match(nil, _string), do: nil

  defp match(group, string) do
    match =
      group
      |> Keyword.fetch!(:regex)
      |> Regex.run(string)

    {group, match}
  end

  defp parse_device({user_agent, acc}, patterns, index) do
    device = find_and_parse(patterns, index, user_agent, Device)
    {user_agent, Map.put(acc, :device, device)}
  end

  defp parse_os({user_agent, acc}, patterns, index) do
    os = find_and_parse(patterns, index, user_agent, OperatingSystem)
    Map.put(acc, :os, os)
  end

  defp parse_user_agent(user_agent, patterns, index) do
    ua = find_and_parse(patterns, index, user_agent, UA)

    {user_agent, ua}
  end

  defp sanitize(user_agent), do: String.trim(user_agent)

  defp search(groups, nil, string) do
    groups
    |> Enum.find(fn group ->
      group
      |> Keyword.fetch!(:regex)
      |> Regex.match?(string)
    end)
    |> match(string)
  end

  defp search(_groups, %Index{} = index, string), do: Index.find(index, string)
end
