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

  describe "parse/2 with :only" do
    test "resolves only the requested domains, others come back as their empty struct" do
      ua = UAParser.parse(@user_agent, only: [:browser])

      assert to_string(ua) == "Skyfire 2.0"
      assert ua.os == %UAParser.OperatingSystem{}
      assert ua.device == %UAParser.Device{}
    end

    test "defaults to every domain when :only is omitted" do
      assert UAParser.parse(@user_agent, []) == UAParser.parse(@user_agent)
    end

    test "raises on an unknown domain" do
      assert_raise ArgumentError, ~r/invalid :only domain/, fn ->
        UAParser.parse(@user_agent, only: [:bogus])
      end
    end
  end
end
