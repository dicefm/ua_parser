defmodule UAParser.StorageTest do
  use ExUnit.Case

  test "lists storage contents" do
    result = UAParser.Storage.list()

    assert is_tuple(result)
    assert tuple_size(result) == 3
  end

  describe "indexes_for/1" do
    test "returns an index per list for the stored patterns" do
      assert {%UAParser.Index{}, %UAParser.Index{}, %UAParser.Index{}} =
               UAParser.Storage.indexes_for(UAParser.Storage.list())
    end

    test "returns the indexes for a copy of the stored patterns" do
      copy = UAParser.Storage.list() |> :erlang.term_to_binary() |> :erlang.binary_to_term()

      assert UAParser.Storage.indexes_for(copy) == UAParser.Storage.indexes_for(UAParser.Storage.list())
    end

    test "returns nil for other patterns" do
      assert UAParser.Storage.indexes_for({[], [], []}) == nil
    end
  end

  describe "build_indexes/2" do
    test "indexes only the given parts, keeping the other lists as they are" do
      {_ua, _os, devices} = patterns = UAParser.Storage.list()

      assert {%UAParser.Index{}, %UAParser.Index{}, ^devices} =
               UAParser.Storage.build_indexes(patterns, [:browser, :os])
    end

    test "parses an unindexed part the same as an indexed one" do
      patterns = UAParser.Storage.list()
      partial = UAParser.Storage.build_indexes(patterns, [:os])
      full = UAParser.Storage.build_indexes(patterns, [:browser, :os, :device])

      for agent <- [
            "Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_5_7; en-us) AppleWebKit/530.17 (KHTML, like Gecko) Version/4.0 Safari/530.17 Skyfire/2.0",
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"
          ] do
        assert UAParser.Parser.parse(partial, agent) == UAParser.Parser.parse(full, agent)
      end
    end

    test "raises for an unknown part" do
      assert_raise ArgumentError,
                   "expected :indexed_parts to be a subset of [:browser, :os, :device], got: [:engine]",
                   fn -> UAParser.Storage.build_indexes(UAParser.Storage.list(), [:engine]) end
    end
  end
end
