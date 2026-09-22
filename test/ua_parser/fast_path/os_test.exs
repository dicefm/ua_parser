defmodule UAParser.FastPath.OSTest do
  use ExUnit.Case

  alias UAParser.FastPath.OS
  alias UAParser.OperatingSystem

  setup_all do
    OS.warm()
    :ok
  end

  describe "match/1" do
    test "Windows NT build numbers map through the lookup table" do
      ua =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"

      assert %OperatingSystem{family: "Windows", version: version} = OS.match(ua)
      assert to_string(version) == "10"
    end

    test "Windows NT 6.1 maps to Windows 7" do
      ua =
        "Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/60.0.3112.113 Safari/537.36"

      assert %OperatingSystem{family: "Windows", version: version} = OS.match(ua)
      assert to_string(version) == "7"
    end

    test "an unmapped NT build number defers instead of guessing" do
      ua = "Mozilla/5.0 (Windows NT 99.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"
      assert OS.match(ua) == :no_match
    end

    test "Android is checked before the generic Linux branch" do
      ua =
        "Mozilla/5.0 (Linux; Android 13; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Mobile Safari/537.36"

      assert %OperatingSystem{family: "Android", version: version} = OS.match(ua)
      assert to_string(version) == "13"
    end

    test "Chrome OS skips the board-name token between the marker and the version" do
      ua =
        "Mozilla/5.0 (X11; CrOS x86_64 15633.69.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"

      assert %OperatingSystem{family: "Chrome OS", version: version} = OS.match(ua)
      assert to_string(version) == "15633.69.0"
    end

    test "Mac OS X, underscores normalised to dots" do
      ua =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Safari/605.1.15"

      assert %OperatingSystem{family: "Mac OS X", version: version} = OS.match(ua)
      assert to_string(version) == "10.15.7"
    end

    test "Ubuntu is checked before the generic Linux branch" do
      ua = "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0"
      assert %OperatingSystem{family: "Ubuntu"} = OS.match(ua)
    end

    test "bare Linux, no version" do
      ua = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"
      assert %OperatingSystem{family: "Linux"} = OS.match(ua)
    end

    test "an unrecognised string defers" do
      assert OS.match("not a user agent at all") == :no_match
    end
  end
end
