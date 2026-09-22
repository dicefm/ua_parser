defmodule UAParser.FastPath.BrowserTest do
  use ExUnit.Case

  alias UAParser.FastPath.Browser
  alias UAParser.UA

  setup_all do
    Browser.warm()
    :ok
  end

  describe "match/1" do
    test "Chrome desktop" do
      ua =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"

      assert %UA{family: "Chrome", version: version} = Browser.match(ua)
      assert to_string(version) == "125.0.0.0"
    end

    test "desktop Chrome only needs major.minor - patch/build are optional" do
      ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
      assert %UA{family: "Chrome", version: version} = Browser.match(ua)
      assert to_string(version) == "124.0"
    end

    test "a reduced Chrome UA (bare version, no dot) is not claimed" do
      ua =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125 Safari/537.36"

      assert Browser.match(ua) == :no_match
    end

    test "Edge is checked before the generic Chrome branch" do
      ua =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 Edg/124.0.0.0"

      assert %UA{family: "Edge"} = Browser.match(ua)
    end

    test "Chrome Mobile requires a full version and a Mobile token" do
      ua =
        "Mozilla/5.0 (Linux; Android 13; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Mobile Safari/537.36"

      assert %UA{family: "Chrome Mobile"} = Browser.match(ua)
    end

    test "Firefox" do
      ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:128.0) Gecko/20100101 Firefox/128.0"
      assert %UA{family: "Firefox", version: version} = Browser.match(ua)
      assert to_string(version) == "128.0"
    end

    test "Mobile Safari requires a device token, plain Safari doesn't have one" do
      mobile =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

      desktop =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Safari/605.1.15"

      assert %UA{family: "Mobile Safari"} = Browser.match(mobile)
      assert %UA{family: "Safari"} = Browser.match(desktop)
    end

    test "a bot spoofing a Chrome/Safari shape defers instead of guessing" do
      ua =
        "Mozilla/5.0 (Linux; Android 6.0.1; Nexus 5X Build/MMB29P) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.5845.96 Mobile Safari/537.36 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"

      assert Browser.match(ua) == :no_match
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

      assert Browser.match(ua) == :no_match
    end

    test "an unrecognised string defers" do
      assert Browser.match("not a user agent at all") == :no_match
    end
  end
end
