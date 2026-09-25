defmodule UAParser do
  @moduledoc """
  A fast User Agent parser with a widely used API.

  ## How parsing works

  Patterns come in three ordered lists, one each for the browser, the OS
  and the device. For each list, the first pattern whose regex matches
  the user-agent string gives the result.

  Running every regex in order would be slow: the bundled lists have
  hundreds of patterns each. So each bundled pattern has a literal,
  worked out from its regex when the library compiles, that any string
  it matches must contain. For example, `Chrome/(\\d+)` needs `chrome/`.
  For an alternation like `(Googlebot|Bingbot)`, any one of its literals
  is enough.

  At boot, the literals of each list are compiled into a single
  `:binary.compile_pattern/1` pattern. Parsing scans the lowercased
  string once to find the patterns that could match. It then runs just
  those regexes, in list order, so the result is the same as trying
  every pattern. Patterns with no provable literal are always tried.

  To get this speedup:

    * Use `parse/1`, or pass `default_patterns/0` itself to `parse/2` and
      `parse/3`. The index is found by comparing the given patterns
      against the stored ones. For the term `default_patterns/0` returns,
      that's a pointer check. For an equal copy, such as one kept in
      another process's state, it's a full compare that costs about
      100 µs per call.
    * Use the `:only` option of `parse/3` to skip the lists you don't
      need. The device list is the largest.

  Any other patterns are tried one by one, in order.

  ## Configuration

  Each index takes several MB of memory. To index only the parts you
  parse, list them in `:indexed_parts` (all three by default):

      config :ua_parser, indexed_parts: [:browser, :os]

  A part left out still parses the same, by trying its patterns one by
  one.
  """

  alias UAParser.{Parser, Storage}

  @doc """
  Parse a user-agent string into structs

  ## Examples

      iex> agent_string = "Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_5_7; en-us) AppleWebKit/530.17 (KHTML, like Gecko) Version/4.0 Safari/530.17 Skyfire/2.0"
      iex> ua = UAParser.parse(agent_string)
      iex> to_string(ua)
      "Skyfire 2.0"
      iex> to_string(ua.os)
      "Mac OS X 10.5.7"
      iex> to_string(ua.device)
      "Mac"

  """
  def parse(nil), do: parse("")
  def parse(ua), do: parse(ua, default_patterns())
  def parse(ua, pattern), do: pattern |> searchable() |> Parser.parse(ua)

  @doc """
  Parse a user-agent string against `patterns` with options.

  `patterns` is a `{user_agent, os, device}` tuple of patterns, such as
  `default_patterns/0`.

  ## Options

    * `:only` - which parts to parse, a subset of `[:browser, :os, :device]`.
      A part left out comes back as if nothing matched it. Defaults to all
      three.

  ## Examples

      iex> agent_string = "Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_5_7; en-us) AppleWebKit/530.17 (KHTML, like Gecko) Version/4.0 Safari/530.17 Skyfire/2.0"
      iex> ua = UAParser.parse(agent_string, UAParser.default_patterns(), only: [:browser, :os])
      iex> to_string(ua)
      "Skyfire 2.0"
      iex> to_string(ua.os)
      "Mac OS X 10.5.7"
      iex> ua.device
      %UAParser.Device{}

  """
  def parse(ua, patterns, opts), do: patterns |> searchable() |> Parser.parse(ua, opts)

  @doc """
  The patterns `parse/1` uses: the bundled `patterns.yml`, as a
  `{user_agent, os, device}` tuple.
  """
  def default_patterns, do: Storage.list()

  # The bundled patterns are searched through their indexes; other patterns
  # have none, so they're scanned in order.
  defp searchable(patterns), do: Storage.indexes_for(patterns) || patterns
end
