defmodule UAParser.Storage do
  @moduledoc """
  Load pattern data at boot time and store it in persistent_term.
  """

  alias UAParser.{Index, Processor}
  alias UAParser.Index.Requirements

  Application.start(:yamerl)

  @doc """
  Loads the user agent, operating system, and device patterns from the YAML file
  into persistent_term, along with an index for each list.

  Returns `:ok` on success.
  """
  @spec load_table() :: :ok
  def load_table do
    patterns = read_from_yaml()

    simple_put(patterns)
    :persistent_term.put(indexes_key(), build_indexes(patterns, Requirements.bundled()))

    :ok
  end

  defp build_indexes({user_agents, os, devices}, {ua_requirements, os_requirements, device_requirements}) do
    {Index.build(user_agents, ua_requirements), Index.build(os, os_requirements),
     Index.build(devices, device_requirements)}
  end

  defp read_from_yaml do
    :ua_parser
    |> :code.priv_dir()
    |> Kernel.++(~c"/patterns.yml")
    |> :yamerl_constr.file([])
    |> Processor.process()
  end

  @doc """
  Returns a tuple containing all three pattern lists:
  `{user_agent_patterns, os_patterns, device_patterns}`.
  """
  @spec list() :: {term(), term(), term()}
  def list do
    simple_get()
  end

  # The indexes built for the stored patterns, as `{user_agent, os, device}`,
  # when `patterns` are the stored patterns, otherwise nil. `list/0` hands out
  # the stored term itself, so the common case is a pointer comparison.
  @doc false
  @spec indexes_for(term()) :: {Index.t(), Index.t(), Index.t()} | nil
  def indexes_for(patterns) do
    if patterns === simple_get(), do: :persistent_term.get(indexes_key())
  end

  defp simple_get do
    :persistent_term.get(key())
  end

  defp simple_put(value) do
    :persistent_term.put(key(), value)
  end

  defp key do
    {__MODULE__, :patterns}
  end

  defp indexes_key, do: {__MODULE__, :indexes}
end
