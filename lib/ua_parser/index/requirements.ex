defmodule UAParser.Index.Requirements do
  @moduledoc false

  # Requirements for the bundled patterns, mined at compile time and embedded
  # as a literal. Only regex sources are read here; regexes are still
  # compiled at runtime by `UAParser.Storage`. `@external_resource`
  # recompiles this module whenever `priv/patterns.yml` changes.

  alias UAParser.Index.RequirementMiner
  alias UAParser.Processor

  Application.start(:yamerl)

  @patterns_path Path.expand("../../../priv/patterns.yml", __DIR__)
  @external_resource @patterns_path

  [user_agents, os, devices] =
    @patterns_path
    |> String.to_charlist()
    |> :yamerl_constr.file([])
    |> Processor.sources()

  mine = fn groups ->
    Enum.map(groups, fn group -> group |> Keyword.fetch!(:regex) |> RequirementMiner.requirement() end)
  end

  @user_agents mine.(user_agents)
  @os mine.(os)
  @devices mine.(devices)

  @doc """
  Requirements mined for the bundled user-agent, OS and device patterns, as
  `{user_agent, os, device}` - in the same order, and the same length, as
  the pattern lists `UAParser.Storage.list/0` returns.
  """
  def bundled, do: {@user_agents, @os, @devices}
end
