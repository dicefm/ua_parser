defmodule UAParser.FastPath do
  @moduledoc """
  Compile-time-generated, regex-free matchers for the small set of
  high-volume, regular UA shapes (`priv/ua_shapes.yml`) that make up most
  real traffic - browser, OS and device, mirroring the same three
  independent pattern lists `UAParser.Index` works over. `UAParser.Parser`
  tries each of `Browser`/`OS`/`Device` first; anything a matcher doesn't
  recognise (`:no_match`) falls back to `UAParser.Index` + `Regex.run`,
  unchanged.

  Every shape is grounded in `patterns.yml`'s actual winning rule for it,
  verified against real production traffic before being trusted - several
  are non-obvious (Chrome's version only needs major.minor; Windows NT
  build numbers map through a hardcoded lookup table; iPhone/iPad must be
  checked before Mac because they spoof "like Mac OS X"). See
  `priv/ua_shapes.yml`'s comments for the specifics behind each branch.
  """

  alias UAParser.FastPath.{Browser, Device, OS}
  alias UAParser.Version

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
