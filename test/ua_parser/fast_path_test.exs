defmodule UAParser.FastPathTest do
  use ExUnit.Case

  alias UAParser.{FastPath, Version}

  describe "version/1" do
    test "splits a dotted version into major/minor/patch/patch_minor" do
      assert FastPath.version("128.0.6613.120") == %Version{major: "128", minor: "0", patch: "6613", patch_minor: "120"}
    end

    test "handles fewer than four parts" do
      assert FastPath.version("128.0") == %Version{major: "128", minor: "0", patch: nil, patch_minor: nil}
      assert FastPath.version("128") == %Version{major: "128", minor: nil, patch: nil, patch_minor: nil}
    end

    test "an empty string means no version at all" do
      assert FastPath.version("") == %Version{}
    end
  end
end
