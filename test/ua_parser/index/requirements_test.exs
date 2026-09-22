defmodule UAParser.Index.RequirementsTest do
  use ExUnit.Case

  alias UAParser.Index.{RequirementMiner, Requirements}
  alias UAParser.Storage

  describe "bundled/0" do
    test "matches a fresh mining pass over the same patterns, in the same order" do
      {user_agents, os, devices} = Storage.list()
      {ua_reqs, os_reqs, device_reqs} = Requirements.bundled()

      for {label, groups, requirements} <- [
            {"user_agent", user_agents, ua_reqs},
            {"os", os, os_reqs},
            {"device", devices, device_reqs}
          ] do
        assert length(groups) == length(requirements), "#{label}: length mismatch"

        fresh =
          Enum.map(groups, fn group ->
            group |> Keyword.fetch!(:regex) |> Regex.source() |> RequirementMiner.requirement()
          end)

        assert fresh == requirements, "#{label}: compile-time requirements diverge from a fresh mining pass"
      end
    end
  end
end
