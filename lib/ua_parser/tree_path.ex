defmodule UAParser.TreePath do
  @moduledoc """
  Regex-free matchers for the small set of high-volume UA shapes in
  `priv/ua_shapes.yml` - browser, OS and device.

  Each shape's branches are compiled, at build time, into actual Elixir
  function clauses (see `UAParser.TreePath.Browser`'s moduledoc) - trying
  a branch is then ordinary pattern-matched function dispatch, compiled
  into BEAM code, rather than a data structure walked or a regex
  compiled and run at every call.

  `browser/1`, `device/1` and `os/1` return `:no_match` when nothing
  here recognises the shape; `UAParser.Parser` is the only caller, and
  falls back to `UAParser.RegexPath` when it gets `:no_match`.
  """

  alias UAParser.TreePath.{Browser, Device, OS}
  alias UAParser.Version

  @doc """
  Resolves the browser for `user_agent`, or `:no_match`.

  ## Examples

      iex> UAParser.TreePath.browser("Mozilla/5.0 Chrome/128.0.0.0 Safari/537.36").family
      "Chrome"

      iex> UAParser.TreePath.browser("not a user agent at all")
      :no_match
  """
  @spec browser(binary()) :: UAParser.UA.t() | :no_match
  def browser(user_agent), do: Browser.match(user_agent)

  @doc """
  Resolves the device for `user_agent`, or `:no_match`.

  ## Examples

      iex> agent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)"
      iex> UAParser.TreePath.device(agent).family
      "iPhone"

      iex> UAParser.TreePath.device("not a user agent at all")
      :no_match
  """
  @spec device(binary()) :: UAParser.Device.t() | :no_match
  def device(user_agent), do: Device.match(user_agent)

  @doc """
  Resolves the OS for `user_agent`, or `:no_match`.

  ## Examples

      iex> agent = "Mozilla/5.0 (Linux; Android 14) Chrome/125.0.0.0 Mobile Safari/537.36"
      iex> UAParser.TreePath.os(agent).family
      "Android"

      iex> UAParser.TreePath.os("not a user agent at all")
      :no_match
  """
  @spec os(binary()) :: UAParser.OperatingSystem.t() | :no_match
  def os(user_agent), do: OS.match(user_agent)

  @doc "Compiles every shape matcher's patterns. Call once, at boot."
  @spec warm() :: :ok
  def warm do
    Browser.warm()
    OS.warm()
    Device.warm()
    :ok
  end

  @doc false
  @spec version(binary()) :: Version.t()
  def version(""), do: %Version{}

  def version(raw) do
    [major, minor, patch, patch_minor | _] = String.split(raw, ".") ++ [nil, nil, nil, nil]
    %Version{major: major, minor: minor, patch: patch, patch_minor: patch_minor}
  end
end
