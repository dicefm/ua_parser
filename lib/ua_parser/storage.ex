defmodule UAParser.Storage do
  @moduledoc """
  Load pattern data at boot time and store it in persistent_term.

  Alongside the patterns themselves an `UAParser.Index` is built for each
  of the three lists, so `UAParser.Parser` can skip regexes that cannot
  match rather than running the whole list. Both are stored together, and
  `indexes_for/1` hands back the indexes only for the stored patterns -
  a caller parsing with its own pattern list gets `nil` and the plain
  linear scan.
  """

  alias UAParser.{Index, Processor}

  Application.start(:yamerl)

  @doc """
  Loads the user agent, operating system, and device patterns from the YAML file
  into persistent_term, and builds an index for each of them.

  Returns `:ok` on success.
  """
  @spec load_table() :: :ok
  def load_table do
    patterns = read_from_yaml()

    simple_put({patterns, build_indexes(patterns)})

    :ok
  end

  defp build_indexes({user_agents, os, devices}) do
    {Index.build(user_agents), Index.build(os), Index.build(devices)}
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
    {patterns, _indexes} = simple_get()

    patterns
  end

  @doc """
  Returns the indexes built for the stored patterns, as
  `{user_agent_index, os_index, device_index}`.
  """
  @spec indexes() :: {Index.t(), Index.t(), Index.t()}
  def indexes do
    {_patterns, indexes} = simple_get()

    indexes
  end

  @doc """
  Returns the indexes if `patterns` is the stored pattern set, otherwise
  `nil`.

  The comparison is against the exact term held in persistent_term, which
  is what `list/0` hands out, so the common case costs a pointer
  comparison.
  """
  @spec indexes_for(term()) :: {Index.t(), Index.t(), Index.t()} | nil
  def indexes_for(patterns) do
    case simple_get() do
      {^patterns, indexes} -> indexes
      _other -> nil
    end
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
end
