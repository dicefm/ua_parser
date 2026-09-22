defmodule UAParser.Processor do
  @moduledoc """
  Prepare a raw YAML document for consumption by the parser by
  converting charlists into strings and compiling our patterns.
  """

  @doc """
  Process a document into Elixir keyword lists and compiled patterns.
  """
  def process(document), do: document |> sources() |> compile()

  @doc """
  Reads and parses a YAML file with yamerl, given its path.
  """
  @spec load_yaml(binary() | charlist()) :: term()
  def load_yaml(path) when is_binary(path), do: path |> String.to_charlist() |> load_yaml()
  def load_yaml(path), do: :yamerl_constr.file(path, [])

  @doc """
  Processes a document into Elixir keyword lists, leaving `:regex` as the
  source string YAML gives it rather than a compiled `Regex`. Used at
  compile time to mine index requirements without compiling every regex on
  the build machine - compiling stays a runtime concern, tied to the exact
  OTP/PCRE build that will run it.
  """
  def sources(document) do
    document
    |> extract
    |> convert
  end

  defp atom_key(key) do
    key
    |> String.Chars.to_string()
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    |> String.to_atom()
  end

  defp compile(groups) do
    # result: {user_agents, os, devices}
    groups
    |> Enum.map(&compile_groups/1)
    |> :erlang.list_to_tuple()
  end

  defp compile_group(group) do
    pattern =
      group
      |> Keyword.fetch!(:regex)
      |> Regex.compile!()

    Keyword.put(group, :regex, pattern)
  end

  defp compile_groups(groups), do: Enum.map(groups, &compile_group/1)

  defp convert([]), do: []

  defp convert([head | tail]) do
    result = Enum.map(head, &to_keyword/1)
    [result | convert(tail)]
  end

  defp extract([document | _]) do
    [{~c"user_agent_parsers", user_agents}, {~c"os_parsers", os}, {~c"device_parsers", devices}] = document

    [user_agents, os, devices]
  end

  defp to_keyword([]), do: []

  defp to_keyword([{key, value} | tails]) do
    keyword = {atom_key(key), String.Chars.to_string(value)}
    [keyword | to_keyword(tails)]
  end
end
