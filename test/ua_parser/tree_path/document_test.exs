defmodule UAParser.TreePath.DocumentTest do
  use ExUnit.Case

  alias UAParser.TreePath.{Document, InvalidShapeError}

  setup do
    path = Path.join(System.tmp_dir!(), "document_test_#{System.unique_integer([:positive])}.yml")
    on_exit(fn -> File.rm(path) end)
    %{path: path}
  end

  describe "section/2" do
    test "raises with a clear message when the section is missing", %{path: path} do
      File.write!(path, "user_agent:\n  branches: []\n")

      assert_raise InvalidShapeError, ~r/missing the top-level "device" section/, fn ->
        Document.section(path, :device)
      end
    end

    test "raises with a clear message when the file has no document at all", %{path: path} do
      File.write!(path, "")

      assert_raise InvalidShapeError, ~r/empty or not a single YAML document/, fn ->
        Document.section(path, :device)
      end
    end
  end

  describe "branches/1" do
    test "raises when the branches key is missing" do
      assert_raise InvalidShapeError, ~r/missing "branches" key/, fn ->
        Document.branches([{~c"foo", ~c"bar"}])
      end
    end

    test "raises when branches isn't a list" do
      assert_raise InvalidShapeError, ~r/expected "branches" to be a list/, fn ->
        Document.branches([{~c"branches", "not a list"}])
      end
    end
  end

  describe "fetch_str!/2" do
    test "raises when the key is missing" do
      assert_raise InvalidShapeError, ~r/missing required "family"/, fn ->
        Document.fetch_str!([{~c"brand", ~c"Apple"}], ~c"family")
      end
    end

    test "returns the value when present" do
      assert Document.fetch_str!([{~c"family", ~c"Chrome"}], ~c"family") == "Chrome"
    end
  end
end
