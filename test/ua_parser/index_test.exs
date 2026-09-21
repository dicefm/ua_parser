defmodule UAParser.IndexTest do
  use ExUnit.Case

  alias UAParser.{Index, Storage}

  doctest UAParser.Index

  # A spread of real user agents plus the shapes that stress the index:
  # alternations, case-classed words, smart TVs, bots and junk.
  @user_agents [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1",
    "Mozilla/5.0 (iPad; CPU OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1",
    "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36",
    "Mozilla/5.0 (Linux; Android 13; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Mobile Safari/537.36",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:126.0) Gecko/20100101 Firefox/126.0",
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36 Edg/125.0.0.0",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 OPR/110.0.0.0",
    "Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_5_7; en-us) AppleWebKit/530.17 (KHTML, like Gecko) Version/4.0 Safari/530.17 Skyfire/2.0",
    "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)",
    "Mozilla/5.0 (compatible; bingbot/2.0; +http://www.bing.com/bingbot.htm)",
    "Mozilla/5.0 (compatible; YandexBot/3.0; +http://yandex.com/bots)",
    "Mozilla/5.0 (compatible; AhrefsBot/7.0; +http://ahrefs.com/robot/)",
    "Mozilla/5.0 (compatible; MJ12bot/v1.4.8; http://mj12bot.com/)",
    "facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)",
    "Twitterbot/1.0",
    "AspiegelBot",
    "PetalBot",
    "Mozilla/5.0 (Linux; Android 10) Mobile Safari/537.36 (compatible; PetalBot;+https://webmaster.petalsearch.com/site/petalbot)",
    "Mozilla/5.0 (compatible) Microsoft Office Outlook 12.0.6425",
    "MSOffice 12",
    "CSimpleSpider/1.0",
    "CrawlDaddy v1",
    "MobileIron/2.26.0",
    "evil-spider the crawler/2.0",
    "Mozilla/5.0 (Windows NT 10.0) SomeIndexer/1.0",
    "python-requests/2.31.0",
    "Go-http-client/1.1",
    "curl/8.0",
    "okhttp/4.9.3",
    "Apache-HttpClient/4.5.13 (Java/17.0.1)",
    "PostmanRuntime/7.36.0",
    "Wget/1.21.3",
    "Opera/9.80 (Linux mips; U; HbbTV/1.1.1 (; Sony; KDL32W650A; PKG3.211EUA; 2013;); ) Presto/2.12.362 Version/12.11",
    "HbbTV/1.1.1 ( ;LGE ;NetCast 4.0 ;03.20.30 ;1.0M ;)",
    "HbbTV/1.1.1 (;Samsung;SmartTV2013;T-FXPDEUC-1102.2;;) WebKit",
    "Mozilla/5.0 (SMART-TV; Linux; Tizen 6.5) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/76.0.3809.146 TV Safari/537.36",
    "Roku/DVP-9.10 (509.10E04111A)",
    "AppleTV11,1/11.1",
    "Mozilla/5.0 (PlayStation; PlayStation 5/2.26) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/8.0 Safari/605.1.15",
    "Mozilla/5.0 (X11; CrOS x86_64 15633.69.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
    "ArcGIS Client Using WinInet",
    "OperationsDashboard-Windows-10.1.2",
    "GeoEvent Server 10.5.1",
    "Mozilla/5.0",
    "",
    "not a user agent at all",
    "\\/\\/ [] () {} weird escaping"
  ]

  defp categories do
    {user_agents, os, devices} = Storage.list()

    [{"user_agent", user_agents}, {"os", os}, {"device", devices}]
  end

  defp regex(group), do: Keyword.fetch!(group, :regex)

  defp matches?(group, string), do: group |> regex() |> Regex.match?(string)

  defp run(group, string), do: group |> regex() |> Regex.run(string)

  # The reference implementation: scan the whole list in order.
  defp linear_find(groups, string) do
    case Enum.find(groups, &matches?(&1, string)) do
      nil -> nil
      group -> {group, run(group, string)}
    end
  end

  describe "find/2" do
    test "returns exactly what a full linear scan returns, for every pattern list" do
      for {name, groups} <- categories() do
        index = Index.build(groups)

        for user_agent <- @user_agents do
          assert Index.find(index, user_agent) == linear_find(groups, user_agent),
                 "#{name} index disagreed with a linear scan for #{inspect(user_agent)}"
        end
      end
    end
  end

  describe "candidates/2" do
    test "never excludes a pattern that actually matches" do
      for {name, groups} <- categories() do
        index = Index.build(groups)

        for user_agent <- @user_agents do
          matching =
            groups
            |> Enum.with_index()
            |> Enum.filter(fn {group, _position} -> matches?(group, user_agent) end)
            |> MapSet.new(fn {_group, position} -> position end)

          candidates = index |> Index.candidates(user_agent) |> MapSet.new()
          missed = MapSet.difference(matching, candidates)

          assert MapSet.size(missed) == 0,
                 "#{name} index dropped matching pattern(s) #{inspect(MapSet.to_list(missed))} " <>
                   "for #{inspect(user_agent)}"
        end
      end
    end

    test "returns candidates in the pattern list's original order" do
      {user_agents, _os, _devices} = Storage.list()
      index = Index.build(user_agents)
      candidates = Index.candidates(index, "Mozilla/5.0 (Linux; Android 14) Chrome/125.0.0.0 Mobile Safari/537.36")

      assert candidates == Enum.sort(candidates)
      assert candidates == Enum.uniq(candidates)
    end

    test "narrows the candidate set well below the full pattern list" do
      {user_agents, _os, _devices} = Storage.list()
      index = Index.build(user_agents)

      candidates =
        Index.candidates(
          index,
          "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
        )

      assert length(candidates) < div(length(user_agents), 2)
    end
  end

  describe "requirement/1" do
    test "a plain literal is its own requirement" do
      assert Index.requirement("ArcGIS Client Using WinInet") == {:all, "arcgis client using wininet"}
    end

    test "escaped metacharacters count as literal text" do
      assert Index.requirement("arcgisearth\\/(\\d+)\\.(\\d+)") == {:all, "arcgisearth/"}
    end

    test "a quantified character cannot extend the run" do
      assert Index.requirement("Colou?r/(\\d+)") == {:all, "colo"}
    end

    test "a mandatory group's content is mined" do
      assert Index.requirement("(GeoEvent Server) (\\d+)") == {:all, "geoevent server"}
      assert Index.requirement("(OperationsDashboard)-(?:Windows)-(\\d+)") == {:all, "operationsdashboard"}
    end

    test "a quantified group's content is not mined" do
      assert Index.requirement("(?:GeoEvent Server)?SomeOtherThing") == {:all, "someotherthing"}
    end

    test "an alternation becomes an any-of requirement" do
      assert {:any, literals} = Index.requirement("\\b(MobileIron|FireWeb|ANTGalio)/(\\d+)")
      assert Enum.sort(literals) == ["antgalio", "fireweb", "mobileiron"]
    end

    test "an alternation with a branch that yields nothing is not provable" do
      assert Index.requirement("(Spider|\\d+)/(\\d+)") == nil
      assert Index.requirement("(?:Spider|)/(\\d+)") == nil
    end

    test "a top level alternation is not provable" do
      assert Index.requirement("AspiegelBot|PetalBot") == nil
    end

    test "alternation inside a group leaves literals outside it usable" do
      assert Index.requirement("(Collector|Explorer|Workforce)-Application/(\\d+)") == {:all, "-application/"}
    end

    test "lookarounds are never mined" do
      assert Index.requirement("(?=Chromium)Safari") == {:all, "safari"}
      assert Index.requirement("(?!Chromium)Safari") == {:all, "safari"}
    end

    test "a range or negated character class breaks the run" do
      assert Index.requirement("HbbTV/\\d+\\.\\d+ \\(.{0,30}; ?([a-zA-Z]+)") == {:all, "hbbtv/"}
      assert Index.requirement("Build[a-z]{1,10}Version") == {:all, "version"}
      assert Index.requirement("Build[^x]Version") == {:all, "version"}
    end

    test "a class whose members all fold to one character extends the run" do
      assert Index.requirement("[Ss]pider/(\\d+)") == {:all, "spider/"}
      assert Index.requirement("[Ss][Pp][Ii][Dd][Ee][Rr]") == {:all, "spider"}
      assert Index.requirement("Web[Cc]rawler") == {:all, "webcrawler"}
    end

    test "a quantified single-fold class still cannot extend the run" do
      assert Index.requirement("Spider[Bb]?Crawler") == {:all, "crawler"}
    end

    test "an any-of set nested inside a mandatory group is still required" do
      assert {:any, literals} =
               Index.requirement("^.{0,200}?([A-Za-z0-9]{0,50}(?:[Aa]rchiver|[Bb]ot|[Ss]pider))/(\\d+)")

      assert Enum.sort(literals) == ["archiver", "bot", "spider"]
    end

    test "a wildcard breaks the run" do
      assert Index.requirement("Mozilla.{1,200}(Ddg)/(\\d+)") == {:all, "mozilla"}
    end

    test "a run shorter than the minimum is not worth indexing" do
      assert Index.requirement("(\\d+)a(\\d+)") == nil
    end

    test "every bundled pattern yields a well formed requirement" do
      for {_name, groups} <- categories(), group <- groups do
        source = group |> regex() |> Regex.source()

        assert Index.requirement(source) == nil or
                 match?({:all, _literal}, Index.requirement(source)) or
                 match?({:any, _literals}, Index.requirement(source))
      end
    end
  end

  describe "build/1" do
    test "handles an empty pattern list" do
      index = Index.build([])

      assert Index.candidates(index, "anything") == []
      assert Index.find(index, "anything") == nil
    end

    test "leaves only a small tail of patterns that must always be tested" do
      for {name, groups} <- categories() do
        index = Index.build(groups)

        assert length(index.always) < div(length(groups), 4),
               "#{name}: #{length(index.always)} of #{length(groups)} patterns are unindexed"
      end
    end
  end
end
