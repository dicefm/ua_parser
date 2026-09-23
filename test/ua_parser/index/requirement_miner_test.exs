defmodule UAParser.Index.RequirementMinerTest do
  use ExUnit.Case

  alias UAParser.Index.RequirementMiner
  alias UAParser.Storage

  doctest UAParser.Index.RequirementMiner

  describe "requirement/1" do
    test "an empty or non-ASCII class breaks the run" do
      assert RequirementMiner.requirement("Opera[]Mini") == {:all, "opera"}
      assert RequirementMiner.requirement("Brow[é]ser/1") == {:all, "ser/1"}
    end

    test "does not raise on a truncated source" do
      for source <- ["(Chrome", "Chrome{3", "Chrome[ab", "(Safari[ab"] do
        assert {:all, _literal} = RequirementMiner.requirement(source)
      end
    end

    test "a plain literal is its own requirement" do
      assert RequirementMiner.requirement("ArcGIS Client Using WinInet") == {:all, "arcgis client using wininet"}
    end

    test "escaped metacharacters count as literal text" do
      assert RequirementMiner.requirement("arcgisearth\\/(\\d+)\\.(\\d+)") == {:all, "arcgisearth/"}
    end

    test "a quantified character cannot extend the run" do
      assert RequirementMiner.requirement("Colou?r/(\\d+)") == {:all, "colo"}
    end

    test "a mandatory group's content is mined" do
      assert RequirementMiner.requirement("(GeoEvent Server) (\\d+)") == {:all, "geoevent server"}
      assert RequirementMiner.requirement("(OperationsDashboard)-(?:Windows)-(\\d+)") == {:all, "operationsdashboard"}
    end

    test "a quantified group's content is not mined" do
      assert RequirementMiner.requirement("(?:GeoEvent Server)?SomeOtherThing") == {:all, "someotherthing"}
    end

    test "an alternation becomes an any-of requirement" do
      assert {:any, literals} = RequirementMiner.requirement("\\b(MobileIron|FireWeb|ANTGalio)/(\\d+)")
      assert Enum.sort(literals) == ["antgalio", "fireweb", "mobileiron"]
    end

    test "an alternation with a branch that yields nothing is not provable" do
      assert RequirementMiner.requirement("(Spider|\\d+)/(\\d+)") == nil
      assert RequirementMiner.requirement("(?:Spider|)/(\\d+)") == nil
    end

    test "a top level alternation is not provable" do
      assert RequirementMiner.requirement("AspiegelBot|PetalBot") == nil
    end

    test "alternation inside a group leaves literals outside it usable" do
      assert RequirementMiner.requirement("(Collector|Explorer|Workforce)-Application/(\\d+)") ==
               {:all, "-application/"}
    end

    test "lookarounds are never mined" do
      assert RequirementMiner.requirement("(?=Chromium)Safari") == {:all, "safari"}
      assert RequirementMiner.requirement("(?!Chromium)Safari") == {:all, "safari"}
    end

    test "a range or negated character class breaks the run" do
      assert RequirementMiner.requirement("HbbTV/\\d+\\.\\d+ \\(.{0,30}; ?([a-zA-Z]+)") == {:all, "hbbtv/"}
      assert RequirementMiner.requirement("Build[a-z]{1,10}Version") == {:all, "version"}
      assert RequirementMiner.requirement("Build[^x]Version") == {:all, "version"}
    end

    test "a class whose members all fold to one character extends the run" do
      assert RequirementMiner.requirement("[Ss]pider/(\\d+)") == {:all, "spider/"}
      assert RequirementMiner.requirement("[Ss][Pp][Ii][Dd][Ee][Rr]") == {:all, "spider"}
      assert RequirementMiner.requirement("Web[Cc]rawler") == {:all, "webcrawler"}
    end

    test "a quantified single-fold class still cannot extend the run" do
      assert RequirementMiner.requirement("Spider[Bb]?Crawler") == {:all, "crawler"}
    end

    test "an any-of set nested inside a mandatory group is still required" do
      assert {:any, literals} =
               RequirementMiner.requirement("^.{0,200}?([A-Za-z0-9]{0,50}(?:[Aa]rchiver|[Bb]ot|[Ss]pider))/(\\d+)")

      assert Enum.sort(literals) == ["archiver", "bot", "spider"]
    end

    test "a wildcard breaks the run" do
      assert RequirementMiner.requirement("Mozilla.{1,200}(Ddg)/(\\d+)") == {:all, "mozilla"}
    end

    test "a run shorter than the minimum is not worth indexing" do
      assert RequirementMiner.requirement("(\\d+)a(\\d+)") == nil
    end

    test "every bundled pattern yields a well formed requirement" do
      {user_agents, os, devices} = Storage.list()

      for group <- user_agents ++ os ++ devices do
        source = group |> Keyword.fetch!(:regex) |> Regex.source()

        assert RequirementMiner.requirement(source) == nil or
                 match?({:all, _literal}, RequirementMiner.requirement(source)) or
                 match?({:any, _literals}, RequirementMiner.requirement(source))
      end
    end
  end

  describe "tokenize/1" do
    test "a plain literal becomes a run of :lit nodes" do
      assert {:ok, [{:lit, "a"}, {:lit, "b"}]} = RequirementMiner.tokenize("ab")
    end

    test "a foldable class becomes a :fold node" do
      assert {:ok, [{:fold, ?b}]} = RequirementMiner.tokenize("[Bb]")
    end

    test "a non-foldable class becomes a :break" do
      assert {:ok, [:break]} = RequirementMiner.tokenize("[a-z]")
    end

    test "a quantified literal is dropped in favour of a :break" do
      assert {:ok, [:break]} = RequirementMiner.tokenize("a?")
    end

    test "an anchor is preserved without breaking the surrounding run" do
      assert {:ok, [:anchor, {:lit, "a"}]} = RequirementMiner.tokenize("^a")
    end

    test "a mandatory group becomes a nested :group scope" do
      assert {:ok, [{:group, {:one, [{:lit, "a"}]}}]} = RequirementMiner.tokenize("(a)")
      assert {:ok, [{:group, {:any, [[{:lit, "a"}], [{:lit, "b"}]]}}]} = RequirementMiner.tokenize("(a|b)")
    end

    test "a quantified group becomes a :break, its content never tokenized" do
      assert {:ok, [:break]} = RequirementMiner.tokenize("(a|b)?")
    end

    test "a bare top level alternation is unprovable" do
      assert RequirementMiner.tokenize("a|b") == :unprovable
    end
  end

  describe "analyze/1" do
    test "concatenates a run of literals" do
      assert RequirementMiner.analyze([{:lit, "a"}, {:lit, "b"}]) == {"ab", []}
    end

    test "a break starts a new run and keeps the longest one seen" do
      assert RequirementMiner.analyze([{:lit, "a"}, {:lit, "b"}, :break, {:lit, "c"}]) == {"ab", []}
      assert RequirementMiner.analyze([{:lit, "a"}, :break, {:lit, "b"}, {:lit, "c"}]) == {"bc", []}
    end

    test "an anchor does not start a new run" do
      assert RequirementMiner.analyze([{:lit, "a"}, :anchor, {:lit, "b"}]) == {"ab", []}
    end

    test "a mandatory group's literal competes as its own candidate" do
      assert RequirementMiner.analyze([{:lit, "ab"}, {:group, {:one, [{:lit, "c"}]}}]) == {"ab", []}
      assert RequirementMiner.analyze([{:lit, "a"}, {:group, {:one, [{:lit, "bcd"}]}}]) == {"bcd", []}
    end

    test "an any-set from a group is harvested, not merged into the run" do
      assert RequirementMiner.analyze([{:group, {:any, [[{:lit, "a"}], [{:lit, "b"}]]}}]) ==
               {"", [["a", "b"]]}
    end

    test "an any-set nested inside a mandatory group still propagates up" do
      inner = {:group, {:any, [[{:lit, "x"}], [{:lit, "y"}]]}}
      assert RequirementMiner.analyze([{:group, {:one, [inner]}}]) == {"", [["x", "y"]]}
    end
  end
end
