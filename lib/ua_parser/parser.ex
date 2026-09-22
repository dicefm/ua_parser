defmodule UAParser.Parser do
  @moduledoc """
  Handle parsing the user-agent string.

  Each of browser/OS/device is resolved in two layers: `UAParser.FastPath`
  is tried first - a small set of common, regex-free shapes covering most
  real traffic - and `UAParser.RegexPath` is the fallback for whatever it
  doesn't recognise, picking the same pattern `patterns.yml` would.
  """

  alias UAParser.{FastPath, RegexPath, Storage}

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
      try_fast_path(index, FastPath.Browser, user_agent, fn ->
        RegexPath.ua(patterns, index, user_agent)
      end)

    {user_agent, ua}
  end

  defp parse_device({user_agent, acc}, patterns, index) do
    device =
      try_fast_path(index, FastPath.Device, user_agent, fn ->
        RegexPath.device(patterns, index, user_agent)
      end)

    {user_agent, Map.put(acc, :device, device)}
  end

  defp parse_os({user_agent, acc}, patterns, index) do
    os =
      try_fast_path(index, FastPath.OS, user_agent, fn ->
        RegexPath.os(patterns, index, user_agent)
      end)

    Map.put(acc, :os, os)
  end

  # FastPath only applies to the bundled patterns (index present - a
  # caller-supplied pattern list gets nil, same as UAParser.Index does),
  # since every shape is grounded in the bundled patterns.yml's specific
  # regexes, not whatever a caller happens to pass in.
  defp try_fast_path(nil, _matcher, _user_agent, regex_path), do: regex_path.()

  defp try_fast_path(_index, matcher, user_agent, regex_path) do
    case matcher.match(user_agent) do
      :no_match -> regex_path.()
      result -> result
    end
  end

  defp sanitize(user_agent), do: String.trim(user_agent)
end
