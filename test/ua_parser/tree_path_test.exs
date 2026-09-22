defmodule UAParser.TreePathTest do
  use ExUnit.Case

  doctest UAParser.TreePath

  alias UAParser.{Device, OperatingSystem, TreePath, UA, Version}

  describe "version/1" do
    test "splits a dotted version into major/minor/patch/patch_minor" do
      assert TreePath.version("128.0.6613.120") == %Version{major: "128", minor: "0", patch: "6613", patch_minor: "120"}
    end

    test "handles fewer than four parts" do
      assert TreePath.version("128.0") == %Version{major: "128", minor: "0", patch: nil, patch_minor: nil}
      assert TreePath.version("128") == %Version{major: "128", minor: nil, patch: nil, patch_minor: nil}
    end

    test "an empty string means no version at all" do
      assert TreePath.version("") == %Version{}
    end
  end

  describe "browser/1" do
    test "Chrome desktop" do
      ua =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"

      assert %UA{family: "Chrome", version: version} = TreePath.browser(ua)
      assert to_string(version) == "125.0.0.0"
    end

    test "desktop Chrome only needs major.minor - patch/build are optional" do
      ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
      assert %UA{family: "Chrome", version: version} = TreePath.browser(ua)
      assert to_string(version) == "124.0"
    end

    test "a reduced Chrome UA (bare version, no dot) is not claimed" do
      ua =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125 Safari/537.36"

      assert TreePath.browser(ua) == :no_match
    end

    test "Edge is checked before the generic Chrome branch" do
      ua =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 Edg/124.0.0.0"

      assert %UA{family: "Edge"} = TreePath.browser(ua)
    end

    test "Chrome Mobile requires a full version and a Mobile token" do
      ua =
        "Mozilla/5.0 (Linux; Android 13; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Mobile Safari/537.36"

      assert %UA{family: "Chrome Mobile"} = TreePath.browser(ua)
    end

    test "Firefox" do
      ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:128.0) Gecko/20100101 Firefox/128.0"
      assert %UA{family: "Firefox", version: version} = TreePath.browser(ua)
      assert to_string(version) == "128.0"
    end

    test "Mobile Safari requires a device token, plain Safari doesn't have one" do
      mobile =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

      desktop =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Safari/605.1.15"

      assert %UA{family: "Mobile Safari"} = TreePath.browser(mobile)
      assert %UA{family: "Safari"} = TreePath.browser(desktop)
    end

    test "a bot spoofing a Chrome/Safari shape defers instead of guessing" do
      ua =
        "Mozilla/5.0 (Linux; Android 6.0.1; Nexus 5X Build/MMB29P) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.5845.96 Mobile Safari/537.36 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"

      assert TreePath.browser(ua) == :no_match
    end

    test "a legacy browser with a Safari-shaped tail is not misclassified as Safari" do
      # Regression: patterns.yml checks a ~60-name legacy browser
      # alternation (Skyfire among them) well before its generic
      # "Version/...Safari/" fallback - this UA has both, and the
      # specific name must win. Caught by the parser integration test
      # (this exact UA is the library's oldest test fixture), not the
      # real-traffic validation this document was built against, since
      # Skyfire is defunct and doesn't appear in current traffic.
      ua =
        "Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_5_7; en-us) AppleWebKit/530.17 (KHTML, like Gecko) Version/4.0 Safari/530.17 Skyfire/2.0"

      assert TreePath.browser(ua) == :no_match
    end
  end

  describe "device/1" do
    test "iPhone, not misclassified as Mac despite spoofing Mac OS X" do
      # "Mac OS" is patterns.yml's broad fallback, but iPhone/iPad UAs
      # also contain "like Mac OS X" for compatibility - iPhone/iPad must
      # be checked first.
      ua =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

      assert %Device{family: "iPhone", brand: "Apple", model: "iPhone"} = TreePath.device(ua)
    end

    test "iPad" do
      ua =
        "Mozilla/5.0 (iPad; CPU OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"

      assert %Device{family: "iPad", brand: "Apple", model: "iPad"} = TreePath.device(ua)
    end

    test "a plain Mac" do
      ua =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Safari/605.1.15"

      assert %Device{family: "Mac", brand: "Apple", model: "Mac"} = TreePath.device(ua)
    end
  end

  describe "os/1" do
    test "Windows NT build numbers map through the lookup table" do
      ua =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"

      assert %OperatingSystem{family: "Windows", version: version} = TreePath.os(ua)
      assert to_string(version) == "10"
    end

    test "Windows NT 6.1 maps to Windows 7" do
      ua =
        "Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/60.0.3112.113 Safari/537.36"

      assert %OperatingSystem{family: "Windows", version: version} = TreePath.os(ua)
      assert to_string(version) == "7"
    end

    test "an unmapped NT build number defers instead of guessing" do
      ua = "Mozilla/5.0 (Windows NT 99.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"
      assert TreePath.os(ua) == :no_match
    end

    test "Android is checked before the generic Linux branch" do
      ua =
        "Mozilla/5.0 (Linux; Android 13; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Mobile Safari/537.36"

      assert %OperatingSystem{family: "Android", version: version} = TreePath.os(ua)
      assert to_string(version) == "13"
    end

    test "Chrome OS skips the board-name token between the marker and the version" do
      ua =
        "Mozilla/5.0 (X11; CrOS x86_64 15633.69.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"

      assert %OperatingSystem{family: "Chrome OS", version: version} = TreePath.os(ua)
      assert to_string(version) == "15633.69.0"
    end

    test "Mac OS X, underscores normalised to dots" do
      ua =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Safari/605.1.15"

      assert %OperatingSystem{family: "Mac OS X", version: version} = TreePath.os(ua)
      assert to_string(version) == "10.15.7"
    end

    test "Ubuntu is checked before the generic Linux branch" do
      ua = "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0"
      assert %OperatingSystem{family: "Ubuntu"} = TreePath.os(ua)
    end

    test "bare Linux, no version" do
      ua = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"
      assert %OperatingSystem{family: "Linux"} = TreePath.os(ua)
    end
  end
end
