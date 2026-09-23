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
end
