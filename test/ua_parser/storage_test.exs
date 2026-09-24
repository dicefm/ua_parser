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
end
