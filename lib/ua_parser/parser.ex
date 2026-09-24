defmodule UAParser.Parser do
  @moduledoc """
  Handle parsing the user-agent string.
  """

  alias UAParser.Index
  alias UAParser.Parsers.{Device, OperatingSystem, UA}

  @parts [:browser, :os, :device]

  @doc """
  Parse a user-agent string given a set of patterns.

  ## Examples

      iex> ua = UAParser.Parser.parse(UAParser.default_patterns(), "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:142.0) Gecko/20100101 Firefox/142.0")
      iex> to_string(ua)
      "Firefox 142.0"
      iex> to_string(ua.os)
      "Windows 10"

  """
  def parse(patterns, user_agent), do: do_parse(patterns, user_agent, @parts)

  @doc """
  Parse a user-agent string given a set of patterns, with options.

  ## Options

    * `:only` - which parts to parse, a subset of `[:browser, :os, :device]`.
      A part left out comes back as if nothing matched it. Defaults to all
      three.

  ## Examples

      iex> ua = UAParser.Parser.parse(UAParser.default_patterns(), "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:142.0) Gecko/20100101 Firefox/142.0", only: [:os])
      iex> ua.family
      nil
      iex> to_string(ua.os)
      "Windows 10"
      iex> ua.device
      %UAParser.Device{}

      iex> UAParser.Parser.parse(UAParser.default_patterns(), "Firefox/142.0", only: [:engine])
      ** (ArgumentError) expected :only to be a subset of [:browser, :os, :device], got: [:engine]

  """
  def parse(patterns, user_agent, opts), do: do_parse(patterns, user_agent, only!(opts))

  defp do_parse({ua_patterns, os_patterns, device_patterns}, user_agent, only) do
    user_agent = String.trim(user_agent)

    ua = maybe_parse(:browser in only, ua_patterns, user_agent, UA)
    os = maybe_parse(:os in only, os_patterns, user_agent, OperatingSystem)
    device = maybe_parse(:device in only, device_patterns, user_agent, Device)

    %{ua | os: os, device: device}
  end

  defp only!(opts) do
    only =
      opts
      |> Keyword.validate!(only: @parts)
      |> Keyword.fetch!(:only)

    case is_list(only) && only -- @parts do
      [] -> only
      _invalid -> raise ArgumentError, "expected :only to be a subset of #{inspect(@parts)}, got: #{inspect(only)}"
    end
  end

  # If the domain is in `only`, we parse it using the given patterns and parser.
  defp maybe_parse(true, patterns, user_agent, parser) do
    patterns
    |> search(user_agent)
    |> parser.parse()
  end

  # If the domain is not in `only`, we return a UA struct with nil values.
  defp maybe_parse(false, _patterns, _user_agent, parser) do
    parser.parse(nil)
  end

  defp search(%Index{} = index, string), do: index |> Index.candidates(string) |> search(string)

  defp search(groups, string) do
    groups
    |> Enum.find(fn group ->
      group
      |> Keyword.fetch!(:regex)
      |> Regex.match?(string)
    end)
    |> match(string)
  end

  defp match(nil, _string), do: nil

  defp match(group, string) do
    match =
      group
      |> Keyword.fetch!(:regex)
      |> Regex.run(string)

    {group, match}
  end
end
