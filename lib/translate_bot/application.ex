defmodule TranslateBot.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      TranslateBot.Cache,
      TranslateBot.Stats,
      TranslateBot.Channels,
      TranslateBot.Consumer
    ]

    opts = [strategy: :one_for_one, name: TranslateBot.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
