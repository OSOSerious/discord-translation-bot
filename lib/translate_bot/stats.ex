defmodule TranslateBot.Stats do
  @moduledoc """
  Translation counters, persisted to DETS so they survive restarts.

  Tracks: total translations, per-language usage, cache hits, and per-channel
  activity. All calls are fire-and-forget safe — counters never block or
  crash translation flows.
  """

  use GenServer

  @table __MODULE__.Counters
  @dets __MODULE__.Counters
  @dets_file ~c"data/stats.dets"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # -- API ------------------------------------------------------------------

  @doc "Record a fresh (non-cached) translation."
  def record_translation(source, target, channel_id) do
    bump({:total}, 1)
    bump({:lang, source, target}, 1)
    if channel_id, do: bump({:channel, channel_id}, 1)
    :ok
  end

  @doc "Record a cache hit."
  def record_cache_hit do
    bump({:cache_hits}, 1)
    :ok
  end

  @doc "Snapshot of all interesting counters."
  def snapshot do
    if table_alive?() do
      :dets.foldl(
        fn
          {{:total}, n}, acc -> Map.put(acc, :total, n)
          {{:cache_hits}, n}, acc -> Map.put(acc, :cache_hits, n)
          {{:lang, s, t}, n}, acc -> Map.update(acc, :langs, %{ {s, t} => n}, &Map.put(&1, {s, t}, n))
          {{:channel, c}, n}, acc -> Map.update(acc, :channels, %{c => n}, &Map.put(&1, c, n))
          _, acc -> acc
        end,
        %{},
        @dets
      )
      |> merge_defaults()
    else
      %{total: 0, cache_hits: 0, langs: %{}, channels: %{}}
    end
  end

  # -- Server ----------------------------------------------------------------

  @impl true
  def init(_opts) do
    File.mkdir_p!(Path.dirname(@dets_file))
    :dets.open_file(@table, file: @dets_file, auto_save: :timer.seconds(30))
    :ok = :dets.sync(@table)
    {:ok, nil}
  end

  @impl true
  def terminate(_reason, _state) do
    :dets.sync(@table)
    :dets.close(@table)
    :ok
  end

  # -- Internals -------------------------------------------------------------

  defp bump(key, n) when is_tuple(key) do
    if table_alive?() do
      # :dets.update_counter/3 (no default-init arity) — seed first if absent.
      case :dets.lookup(@dets, key) do
        [] -> :dets.insert(@dets, {key, n})
        [{^key, current}] -> :dets.insert(@dets, {key, current + n})
        _ -> :ok
      end
    end

    :ok
  rescue
    _ -> :ok
  end

  defp table_alive?, do: :dets.info(@dets) != :undefined

  defp merge_defaults(map) do
    %{
      total: Map.get(map, :total, 0),
      cache_hits: Map.get(map, :cache_hits, 0),
      langs: Map.get(map, :langs, %{}),
      channels: Map.get(map, :channels, %{})
    }
  end
end
