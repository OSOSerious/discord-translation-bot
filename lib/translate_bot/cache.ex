defmodule TranslateBot.Cache do
  @moduledoc """
  ETS-backed translation cache with lazy TTL expiry.

  Reads and writes go straight to a public named table (no GenServer
  round-trip); the GenServer process only owns the table and runs a
  periodic sweep that drops expired entries.

  TTL is configured via `:translate_bot, :cache_ttl_ms` (default 1 hour).
  """

  use GenServer

  @table __MODULE__
  @sweep_interval :timer.minutes(10)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Fetch a cached translation. Returns `{:ok, text}` or `:miss`."
  def fetch(text, source, target) do
    if table_alive?(), do: do_fetch({text, source, target}), else: :miss
  end

  @doc "Store a translation in the cache."
  def put(text, source, target, translated) do
    if table_alive?() do
      :ets.insert(@table, {{text, source, target}, {translated, now()}})
    end

    :ok
  end

  @doc "Drop all cached entries."
  def clear do
    if table_alive?(), do: :ets.delete_all_objects(@table)
    :ok
  end

  @doc "Number of cached entries."
  def size do
    if table_alive?(), do: :ets.info(@table)[:size], else: 0
  end

  # -- Server ---------------------------------------------------------------

  @impl true
  def init(_opts) do
    :ets.new(@table, [:set, :named_table, :public, read_concurrency: true])
    schedule_sweep()
    {:ok, nil}
  end

  @impl true
  def handle_info(:sweep, state) do
    sweep_expired()
    schedule_sweep()
    {:noreply, state}
  end

  # -- Internals ------------------------------------------------------------

  defp do_fetch(key) do
    case :ets.lookup(@table, key) do
      [{^key, {translated, inserted_at}}] ->
        if now() - inserted_at < ttl_ms() do
          {:ok, translated}
        else
          :ets.delete(@table, key)
          :miss
        end

      [] ->
        :miss
    end
  end

  defp sweep_expired do
    horizon = now() - ttl_ms()

    @table
    |> :ets.tab2list()
    |> Enum.each(fn {key, {_value, inserted_at}} ->
      if inserted_at < horizon, do: :ets.delete(@table, key)
    end)
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @sweep_interval)

  defp table_alive?, do: :ets.whereis(@table) != :undefined

  defp ttl_ms, do: Application.get_env(:translate_bot, :cache_ttl_ms, :timer.hours(1))

  defp now, do: System.system_time(:millisecond)
end
