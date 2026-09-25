defmodule UAParser.Storage do
  @moduledoc """
  Load pattern data at boot time and store it in persistent_term.
  """

  alias UAParser.{Index, Processor}
  alias UAParser.Index.Requirements

  Application.start(:yamerl)

  @parts [:browser, :os, :device]

  @doc """
  Loads the user agent, operating system, and device patterns from the YAML file
  into persistent_term, along with an index for each list in the
  `:indexed_parts` config (all three by default).

  Returns `:ok` on success.
  """
  @spec load_table() :: :ok
  def load_table do
    patterns = read_from_yaml()

    simple_put(patterns)

    :persistent_term.put(
      indexes_key(),
      build_indexes(patterns, Application.get_env(:ua_parser, :indexed_parts, @parts))
    )

    :ok
  end

  # One entry per list: its index when the list's part is in `parts`,
  # otherwise the list itself, which parsing scans in order.
  @doc false
  @spec build_indexes({list(), list(), list()}, [atom()]) :: tuple()
  def build_indexes(patterns, parts) do
    parts = indexed_parts!(parts)

    [@parts, Tuple.to_list(patterns), Tuple.to_list(Requirements.bundled())]
    |> Enum.zip_with(fn [part, groups, requirements] ->
      if part in parts, do: Index.build(groups, requirements), else: groups
    end)
    |> List.to_tuple()
  end

  defp indexed_parts!(parts) do
    case is_list(parts) && parts -- @parts do
      [] ->
        parts

      _invalid ->
        raise ArgumentError, "expected :indexed_parts to be a subset of #{inspect(@parts)}, got: #{inspect(parts)}"
    end
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
  # when `patterns` are the stored patterns, otherwise nil. A list left out of
  # `:indexed_parts` is returned as is. `list/0` hands out the stored term
  # itself, so the common case is a pointer comparison.
  @doc false
  @spec indexes_for(term()) :: tuple() | nil
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
