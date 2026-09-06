defmodule HelloLiveView.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        # Persistent windowing state (:dets under /data on a device)
        HelloLiveView.Windows,
        # Start the Telemetry supervisor
        HelloLiveViewWeb.Telemetry,
        # Start the PubSub system
        {Phoenix.PubSub, name: HelloLiveView.PubSub},
        # Start the Endpoint (http/https)
        HelloLiveViewWeb.Endpoint
        # Start a worker by calling: HelloLiveView.Worker.start_link(arg)
        # {HelloLiveView.Worker, arg}
      ] ++ children(target())

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: HelloLiveView.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # List all child processes to be supervised
  def children(:host) do
    [
      # Children that only run on the host
      # Starts a worker by calling: HelloLiveView.Worker.start_link(arg)
      # {HelloLiveView.Worker, arg},
    ]
  end

  def children(target) do
    [
      # Validate new firmware once an interface reports internet
      HelloLiveView.FirmwareValidator
    ] ++ board_children(target) ++ kiosk_children()
  end

  # Board-specific hardware. The recomputer_r22 library only ships on its own
  # target (mix.exs); its supervisor runs the buzzer, RGB LED and UPS monitor.
  defp board_children(:recomputer_r22), do: [{RecomputerR22.Supervisor, []}]
  defp board_children(_target), do: []

  # A kiosk target (config/kiosk.exs) has its own screen. The compositor and
  # browser come after the endpoint in the tree, so there is a page to show.
  defp kiosk_children do
    if Application.get_env(:hello_live_view, :kiosk, false) do
      [HelloLiveView.Kiosk]
    else
      []
    end
  end

  def target() do
    Application.get_env(:hello_live_view, :target)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    HelloLiveViewWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
