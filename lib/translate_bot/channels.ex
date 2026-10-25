defmodule TranslateBot.Channels do
  @moduledoc """
  Per-channel auto-translate toggle, stored in ETS with DETS write-through.

  Survives restarts: `enabled?/1` is seeded from disk on boot and every
  toggle is persisted. Safe to call before the table exists (`false`).
  """

  use GenServer

  @table __MODULE__
  @dets_file ~c"data/channels.dets"
  @dets __MODULE__.Dets

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
        :dets.delete(@dets, channel_id)
        false

      true ->
        :ets.insert(@table, {channel_id, true})
        :dets.insert(@dets, {channel_id, true})
        true
    end
  end

  @doc "Number of channels with auto-translate on."
  def count do
    if table_alive?(), do: :ets.info(@table)[:size], else: 0
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:set, :named_table, :public, read_concurrency: true])

    {:ok, dets} = :dets.open_file(@dets, file: @dets_file, auto_save: :timer.seconds(30))

    # Seed the in-memory table from disk.
    :dets.foldl(fn {channel_id, true}, _acc ->
      :ets.insert(@table, {channel_id, true})
      :ok
    end, :ok, dets)

    {:ok, dets}
  end

  @impl true
  def terminate(_reason, dets) do
    :dets.sync(dets)
    :dets.close(dets)
    :ok
  end

  defp table_alive?, do: :ets.whereis(@table) != :undefined
end
