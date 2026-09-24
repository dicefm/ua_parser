defmodule UAParserTest do
  use ExUnit.Case
  doctest UAParser

  @user_agent "Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_5_7; en-us) AppleWebKit/530.17 (KHTML, like Gecko) Version/4.0 Safari/530.17 Skyfire/2.0"

  test "parse user_agent using default patterns" do
    ua = UAParser.parse(@user_agent)
    assert to_string(ua) == "Skyfire 2.0"
    assert to_string(ua.os) == "Mac OS X 10.5.7"
    assert to_string(ua.device) == "Mac"
  end

  test "parse user_agent using custom patterns" do
    custom_patterns = {
      [
        [
          regex: ~r/(Skyfire)\/(\d+)\.(\d+)(?:\.(\d+))?/,
          family_replacement: "Testing Pattern $1"
        ]
      ],
      [],
      []
    }

    ua = UAParser.parse(@user_agent, custom_patterns)
    assert ua.family == "Testing Pattern Skyfire"
    assert to_string(ua.version) == "2.0"
  end

  test "default_patterns/0 returns the stored patterns" do
    assert UAParser.default_patterns() === UAParser.Storage.list()
  end

  describe "parse/3" do
    test "with :only, parses only the selected parts, the same as parse/1 does" do
      full = UAParser.parse(@user_agent)
      ua = UAParser.parse(@user_agent, UAParser.default_patterns(), only: [:browser, :os])

      assert ua.family == full.family
      assert ua.version == full.version
      assert ua.os == full.os
      assert ua.device == %UAParser.Device{}
    end

    test "a part left out comes back as if nothing matched it" do
      nothing_matched = UAParser.parse(@user_agent, {[], [], []})

      assert UAParser.parse(@user_agent, UAParser.default_patterns(), only: []) == nothing_matched
    end

    test "defaults to all parts" do
      patterns = UAParser.default_patterns()

      assert UAParser.parse(@user_agent, patterns, []) == UAParser.parse(@user_agent)
      assert UAParser.parse(@user_agent, patterns, only: [:browser, :os, :device]) == UAParser.parse(@user_agent)
    end

    test "works with custom patterns" do
      custom_patterns = {[[regex: ~r/(Skyfire)\/(\d+)\.(\d+)/]], [[regex: ~r/(Mac OS X)/]], []}
      ua = UAParser.parse(@user_agent, custom_patterns, only: [:os])

      assert ua.family == nil
      assert ua.os.family == "Mac OS X"
    end

    test "raises on an unknown part" do
      assert_raise ArgumentError, ~r/expected :only to be a subset of/, fn ->
        UAParser.parse(@user_agent, UAParser.default_patterns(), only: [:browser, :engine])
      end
    end

    test "raises when :only is not a list" do
      assert_raise ArgumentError, ~r/expected :only to be a subset of/, fn ->
        UAParser.parse(@user_agent, UAParser.default_patterns(), only: :browser)
      end
    end

    test "raises on an unknown option" do
      assert_raise ArgumentError, ~r/unknown keys \[:except\]/, fn ->
        UAParser.parse(@user_agent, UAParser.default_patterns(), except: [:device])
      end
    end
  end

  describe "with the bundled patterns" do
    @user_agents [
      @user_agent,
      "Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1",
      "Mozilla/5.0 (Linux; Android 14; SM-S918B Build/UP1A; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/139.0.0.0 Mobile Safari/537.36",
      "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)",
      "  python-requests/2.32.3  ",
      "not a user agent at all",
      ""
    ]

    test "returns what a linear scan of the same patterns does" do
      # Not the bundled patterns any more, so scanned linearly, but a pattern
      # that never matches leaves the results unchanged.
      never = [regex: ~r/(?!)/]
      linear = UAParser.default_patterns() |> Tuple.to_list() |> Enum.map(&[never | &1]) |> List.to_tuple()

      for user_agent <- @user_agents, only <- [[:browser, :os, :device], [:browser, :os], [:device], []] do
        assert UAParser.parse(user_agent, UAParser.default_patterns(), only: only) ==
                 UAParser.parse(user_agent, linear, only: only),
               "#{inspect(user_agent)} with only: #{inspect(only)}"
      end
    end
  end
end
