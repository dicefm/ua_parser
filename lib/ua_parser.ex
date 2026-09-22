defmodule UAParser do
  @moduledoc """
  A fast user-agent parser with a widely used API.

  `parse/1` takes a raw user-agent string and returns a `UAParser.UA`
  struct describing the browser, its version, the operating system and
  the device. Browser, OS and device are matched independently, against
  three separate pattern lists, so a UA can have a recognised OS but no
  recognised browser, or vice versa - whichever part isn't recognised
  simply comes back `nil` (or an empty struct), never an error.

  ## How it works

  Matching works against three ordered lists of patterns (derived from
  the BrowserScope project's `patterns.yml`): user-agent, OS and device.
  For each list, parsing finds the *first* pattern whose regex matches
  the string and extracts values (family, version, ...) from its capture
  groups.

  For the bundled patterns, that lookup is accelerated by `UAParser.Index`:
  rather than trying every regex in a list in order until one matches (or
  all of them fail), each pattern is indexed by a literal that must be
  present in the string for it to have any chance of matching, so parsing
  only runs the regex for patterns that could plausibly apply - see
  `UAParser.Index` for the full explanation, including why this can only
  ever skip a pattern that could not have matched anyway. Parsing with
  your own pattern list via `parse/2` is unaffected by any of this and
  always scans linearly.

  ## Examples

  A recognised browser, OS and device:

      iex> agent_string = "Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_5_7; en-us) AppleWebKit/530.17 (KHTML, like Gecko) Version/4.0 Safari/530.17 Skyfire/2.0"
      iex> ua = UAParser.parse(agent_string)
      iex> to_string(ua)
      "Skyfire 2.0"
      iex> to_string(ua.os)
      "Mac OS X 10.5.7"
      iex> to_string(ua.device)
      "Mac"

  A crawler - recognised as a browser and device, but with no OS to report:

      iex> ua = UAParser.parse("Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)")
      iex> to_string(ua)
      "Googlebot 2.1"
      iex> to_string(ua.device)
      "Spider"
      iex> ua.os.family
      nil

  A string nothing recognises - every field comes back empty rather than
  raising:

      iex> ua = UAParser.parse("not a user agent at all")
      iex> to_string(ua)
      "Other"
      iex> ua.family
      nil
      iex> ua.os.family
      nil
      iex> ua.device.family
      nil

  """

  alias UAParser.Parser

  @doc """
  Parses `ua`, a user-agent string, into a `UAParser.UA` struct.

  `nil` is treated the same as an empty string. See the moduledoc for
  what the returned struct looks like and how matching works.
  """
  @spec parse(String.t() | nil) :: UAParser.UA.t()
  def parse(nil), do: parse("")
  def parse(ua), do: Parser.parse(ua, Parser.domains())

  @doc """
  Parses `ua` against a caller-supplied pattern list, or with options
  against the bundled one.

  ## Args

    * `ua` - the raw user-agent string
    * `patterns` - a `{user_agent, os, device}` tuple in the same shape
      `UAParser.Storage.list/0` returns. Useful for testing against a
      small, purpose-built pattern set. Always scans each list linearly:
      the index described in the moduledoc only applies to the bundled
      patterns, since it depends on requirements mined from them ahead
      of time.

  Passing a keyword list instead of `patterns` parses against the
  bundled patterns with:

    * `:only` - which domains to resolve, any subset of `[:browser, :os,
      :device]`. A domain left out comes back as its empty struct, the
      same as when nothing matches. Defaults to all three.

  ## Examples

      iex> agent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) Chrome/125.0.0.0 Mobile Safari/537.36"
      iex> parsed = UAParser.parse(agent, only: [:browser, :os])
      iex> parsed.device
      %UAParser.Device{}
      iex> parsed.os.family
      "iOS"
  """
  @spec parse(String.t() | nil, keyword() | {list(), list(), list()}) :: UAParser.UA.t()
  def parse(nil, opts_or_patterns), do: parse("", opts_or_patterns)
  def parse(ua, patterns) when is_tuple(patterns), do: Parser.parse_with_patterns(patterns, ua)
  def parse(ua, opts) when is_list(opts), do: Parser.parse(ua, only(opts))

  defp only(opts) do
    domains = Parser.domains()

    case Keyword.get(opts, :only, domains) do
      selected when is_list(selected) ->
        case selected -- domains do
          [] ->
            selected

          invalid ->
            raise ArgumentError,
                  "invalid :only domain(s): #{inspect(invalid)}; expected a subset of #{inspect(domains)}"
        end
    end
  end
end
