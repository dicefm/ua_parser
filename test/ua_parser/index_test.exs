defmodule UAParser.IndexTest do
  use ExUnit.Case, async: true

  alias UAParser.Index

  @user_agents [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.1 Safari/605.1.15",
    "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:121.0) Gecko/20100101 Firefox/121.0",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.2210.91",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 OPR/106.0.0.0",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.1 Mobile/15E148 Safari/604.1",
    "Mozilla/5.0 (iPad; CPU OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/120.0.6099.119 Mobile/15E148 Safari/604.1",
    "Mozilla/5.0 (Linux; Android 13; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/23.0 Chrome/115.0.0.0 Mobile Safari/537.36",
    "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.6099.144 Mobile Safari/537.36",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 [FBAN/FBIOS;FBAV/444.0.0.36.113;FBBV/541151234;FBDV/iPhone15,2]",
    "Mozilla/5.0 (compatible; MSIE 10.0; Windows Phone 8.0; Trident/6.0; IEMobile/10.0; ARM; Touch; NOKIA; Lumia 920)",
    "Mozilla/5.0 (SMART-TV; Linux; Tizen 6.0) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/4.0 Chrome/76.0.3809.146 TV Safari/537.36",
    "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)",
    "Mozilla/5.0 (compatible; bingbot/2.0; +http://www.bing.com/bingbot.htm)",
    "curl/8.4.0",
    "MOZILLA/5.0 (WINDOWS NT 10.0; WIN64; X64) APPLEWEBKIT/537.36 (KHTML, LIKE GECKO) CHROME/120.0.0.0 SAFARI/537.36",
    "Something/1.0",
    ""
  ]

  defp group(regex), do: [regex: Regex.compile!(regex)]

  describe "parsing with the bundled patterns" do
    test "returns what a linear scan does" do
      for user_agent <- @user_agents do
        assert UAParser.parse(user_agent) == UAParser.Parser.parse(UAParser.default_patterns(), user_agent)
      end
    end

    test "returns what a linear scan does, for user agents that are not valid UTF-8" do
      for user_agent <- [
            <<206, "Accoona-AI-Agent/1.1.1 (crawler at accoona dot com)">>,
            <<"Mozilla/5.0 (Windows; U; Win98; nl-NL; rv:1.7.2) Gecko/20040804 ", 200, "Netscape/7.2 (ax)">>
          ] do
        assert UAParser.parse(user_agent) == UAParser.Parser.parse(UAParser.default_patterns(), user_agent)
      end
    end
  end

  describe "candidates/2" do
    test "finds a literal that is a prefix of a longer one at the same position" do
      groups = [group("bot/\\d"), group("bot")]
      index = Index.build(groups, [{:all, "bot/"}, {:all, "bot"}])

      assert Index.candidates(index, "Somebot/1") == groups
    end

    test "finds a literal that starts inside another match" do
      groups = [group("abcd"), group("cdef")]
      index = Index.build(groups, [{:all, "abcd"}, {:all, "cdef"}])

      assert Index.candidates(index, "abcdef") == groups
    end

    test "matches literals regardless of case" do
      groups = [group("(?i)chrome")]
      index = Index.build(groups, [{:all, "chrome"}])

      assert Index.candidates(index, "CHROME") == groups
    end

    test "any literal of an :any requirement is enough" do
      groups = [group("googlebot|bingbot")]
      index = Index.build(groups, [{:any, ["googlebot", "bingbot"]}])

      assert Index.candidates(index, "bingbot/2.0") == groups
      assert Index.candidates(index, "other") == []
    end

    test "always includes patterns with no requirement, in list order" do
      [first, chrome, last] = groups = [group("x"), group("chrome"), group("y")]
      index = Index.build(groups, [nil, {:all, "chrome"}, nil])

      assert Index.candidates(index, "Chrome") == [first, chrome, last]
      assert Index.candidates(index, "") == [first, last]
    end
  end
end
