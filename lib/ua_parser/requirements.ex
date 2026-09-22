defmodule UAParser.Requirements do
  @moduledoc """
  Index requirements for the bundled patterns, mined once at compile time
  and embedded as a literal.

  `UAParser.RequirementMiner.requirement/1` reads a regex's *source
  string*, which is plain, portable data - safe to compute here, unlike
  compiling the regex itself, which stays a runtime concern tied to the
  exact OTP/PCRE build that will run it (see `UAParser.Storage`).

  `@external_resource` ties this module to `priv/patterns.yml`, so editing
  it and recompiling is the only "generation step" there is: there is no
  separate file to keep in sync, and nothing that can go stale, so
  `UAParser.Index` does not need to guard against drift.
  """

  alias UAParser.{Processor, RequirementMiner}

  @patterns_path Path.expand("../../priv/patterns.yml", __DIR__)
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
  @spec bundled() ::
          {[RequirementMiner.requirement()], [RequirementMiner.requirement()], [RequirementMiner.requirement()]}
  def bundled, do: {@user_agents, @os, @devices}
end
