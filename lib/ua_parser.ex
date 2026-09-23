defmodule UAParser do
  @moduledoc """
  A fast User Agent parser with a widely used API.
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
