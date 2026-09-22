defmodule UAParser.FastPath.DeviceTest do
  use ExUnit.Case

  alias UAParser.Device, as: DeviceStruct
  alias UAParser.FastPath.Device

  setup_all do
    Device.warm()
    :ok
  end

  describe "match/1" do
    test "iPhone" do
      ua =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

      assert %DeviceStruct{family: "iPhone", brand: "Apple", model: "iPhone"} = Device.match(ua)
    end

    test "iPad" do
      ua =
        "Mozilla/5.0 (iPad; CPU OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"

      assert %DeviceStruct{family: "iPad", brand: "Apple", model: "iPad"} = Device.match(ua)
    end

    test "an iPhone spoofing Mac OS X is not misclassified as Mac" do
      # Regression: "Mac OS" is real patterns.yml's broad fallback, but
      # iPhone/iPad UAs also contain "like Mac OS X" for compatibility -
      # iPhone/iPad must be checked first.
      ua =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

      refute match?(%DeviceStruct{family: "Mac"}, Device.match(ua))
    end

    test "a plain Mac" do
      ua =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Safari/605.1.15"

      assert %DeviceStruct{family: "Mac", brand: "Apple", model: "Mac"} = Device.match(ua)
    end

    test "an unrecognised string defers" do
      assert Device.match("not a user agent at all") == :no_match
    end
  end
end
