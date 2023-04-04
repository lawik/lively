defmodule Lively.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      LivelyWeb.Telemetry,
      # Start the Ecto repository
      Lively.Repo,
      # Start the PubSub system
      {Phoenix.PubSub, name: Lively.PubSub},
      # Start Finch
      {Finch, name: Lively.Finch},
      # {MembraneTranscription.FancyWhisper, model: "base.en"},
       MembraneTranscription.FancyWhisper, model: "tiny.en"},
      # Start the Endpoint (http/https)
      LivelyWeb.Endpoint
      # Start a worker by calling: Lively.Worker.start_link(arg)
      # {Lively.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Lively.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    LivelyWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
