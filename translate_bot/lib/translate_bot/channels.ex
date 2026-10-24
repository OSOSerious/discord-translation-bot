defmodule TranslateBot.Channels do
  @moduledoc """
  Per-channel auto-translate toggle, stored in ETS.

  `enabled?/1` is safe to call before the table exists (returns `false`).
  """

  use GenServer

  @table __MODULE__

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Is auto-translate enabled for this channel?"
  def enabled?(channel_id) do
    table_alive?() and :ets.member(@table, channel_id)
  end

  @doc """
  Toggle auto-translate for a channel. Returns the new state.
  """
  def toggle(channel_id) do
    cond do
      not table_alive?() ->
        false

      enabled?(channel_id) ->
        :ets.delete(@table, channel_id)
        false

      true ->
        :ets.insert(@table, {channel_id, true})
        true
    end
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:set, :named_table, :public, read_concurrency: true])
    {:ok, nil}
  end

  defp table_alive?, do: :ets.whereis(@table) != :undefined
end
