defmodule UAParser.IndexTest do
  use ExUnit.Case, async: true

  alias UAParser.Index

  # Every user agent string in the uap-core test suite
  # (https://github.com/ua-parser/uap-core, Apache-2.0, commit 73e7340),
  # deduplicated, one per line.
  @corpus_path Path.expand("../fixtures/uap_core_user_agents.txt.gz", __DIR__)

  defp group(regex), do: [regex: Regex.compile!(regex)]

  describe "parsing with the bundled patterns" do
    @tag timeout: :infinity
    test "returns what a linear scan does, for every user agent in the uap-core corpus" do
      user_agents = @corpus_path |> File.read!() |> :zlib.gunzip() |> String.split("\n", trim: true)

      # Not the bundled patterns any more, so scanned linearly, but a pattern
      # that never matches leaves the results unchanged.
      never = [regex: ~r/(?!)/]
      linear = UAParser.default_patterns() |> Tuple.to_list() |> Enum.map(&[never | &1]) |> List.to_tuple()

      mismatches =
        user_agents
        |> Task.async_stream(
          fn user_agent ->
            {user_agent, UAParser.parse(user_agent) == UAParser.parse(user_agent, linear)}
          end,
          ordered: false,
          timeout: :infinity
        )
        |> Enum.flat_map(fn {:ok, {user_agent, same?}} -> if same?, do: [], else: [user_agent] end)

      assert length(user_agents) > 30_000
      assert mismatches == []
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
