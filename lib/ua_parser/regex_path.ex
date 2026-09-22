defmodule UAParser.RegexPath do
  @moduledoc """
  Matches a user-agent string against a `patterns.yml` pattern list -
  the fallback for whatever `UAParser.FastPath` doesn't recognise.

  When `index` is present (the bundled patterns), `UAParser.Index` narrows
  down candidates before running `Regex.run`; a caller-supplied pattern
  list gets a plain linear scan instead. Both pick the same pattern: the
  first one in the list whose regex matches.
  """

  alias UAParser.Index
  alias UAParser.Parsers.{Device, OperatingSystem, UA}

  @type patterns :: [Keyword.t()]

  @spec ua(patterns(), Index.t() | nil, binary()) :: UAParser.UA.t()
  def ua(patterns, index, user_agent), do: find_and_parse(patterns, index, user_agent, UA)

  @spec os(patterns(), Index.t() | nil, binary()) :: UAParser.OperatingSystem.t()
  def os(patterns, index, user_agent), do: find_and_parse(patterns, index, user_agent, OperatingSystem)

  @spec device(patterns(), Index.t() | nil, binary()) :: UAParser.Device.t()
  def device(patterns, index, user_agent), do: find_and_parse(patterns, index, user_agent, Device)

  defp find_and_parse(patterns, index, user_agent, module) do
    patterns
    |> search(index, user_agent)
    |> module.parse
  end

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

  defp match(nil, _string), do: nil

  defp match(group, string) do
    match =
      group
      |> Keyword.fetch!(:regex)
      |> Regex.run(string)

    {group, match}
  end
end
