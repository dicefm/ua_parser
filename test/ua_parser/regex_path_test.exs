defmodule UAParser.RegexPathTest do
  use ExUnit.Case

  alias UAParser.{Device, OperatingSystem, RegexPath, Storage, UA}

  @user_agent "Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_5_7; en-us) AppleWebKit/530.17 (KHTML, like Gecko) Version/4.0 Safari/530.17 Skyfire/2.0"

  setup do
    {ua_patterns, os_patterns, device_patterns} = Storage.list()
    {ua_index, os_index, device_index} = Storage.indexes_for(Storage.list())

    %{
      ua_patterns: ua_patterns,
      os_patterns: os_patterns,
      device_patterns: device_patterns,
      ua_index: ua_index,
      os_index: os_index,
      device_index: device_index
    }
  end

  describe "ua/3" do
    test "matches via the index", %{ua_patterns: patterns, ua_index: index} do
      assert %UA{family: "Skyfire", version: version} = RegexPath.ua(patterns, index, @user_agent)
      assert to_string(version) == "2.0"
    end

    test "matches via a plain linear scan when no index is given", %{ua_patterns: patterns} do
      assert %UA{family: "Skyfire"} = RegexPath.ua(patterns, nil, @user_agent)
    end

    test "an unrecognised string returns an empty struct", %{ua_patterns: patterns, ua_index: index} do
      assert RegexPath.ua(patterns, index, "not a user agent at all") == %UA{}
    end
  end

  describe "os/3" do
    test "matches via the index", %{os_patterns: patterns, os_index: index} do
      assert %OperatingSystem{family: "Mac OS X", version: version} = RegexPath.os(patterns, index, @user_agent)
      assert to_string(version) == "10.5.7"
    end

    test "matches via a plain linear scan when no index is given", %{os_patterns: patterns} do
      assert %OperatingSystem{family: "Mac OS X"} = RegexPath.os(patterns, nil, @user_agent)
    end
  end

  describe "device/3" do
    test "matches via the index", %{device_patterns: patterns, device_index: index} do
      assert %Device{family: "Mac"} = RegexPath.device(patterns, index, @user_agent)
    end

    test "matches via a plain linear scan when no index is given", %{device_patterns: patterns} do
      assert %Device{family: "Mac"} = RegexPath.device(patterns, nil, @user_agent)
    end
  end
end
