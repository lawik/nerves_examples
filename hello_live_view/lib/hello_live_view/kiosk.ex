# The kiosk stack only exists on kiosk targets. Myelin is a kiosk-only
# dependency (mix.exs), and the OS processes started here only ship in the
# kiosk systems. Elsewhere this file compiles to nothing and
# HelloLiveView.Application never asks for the module.
if Application.compile_env(:hello_live_view, :kiosk, false) do
  defmodule HelloLiveView.Kiosk do
    @moduledoc """
    Runs the display stack on a kiosk device.

    A kiosk system boots to a black screen; this supervision tree is what puts
    something on it. Three OS processes start in order, each waiting for what
    the previous one provides:

      1. `udevd` enumerates the GPU and input devices so the compositor can
         find them (`HelloLiveView.Kiosk.Udevd`).
      2. `weston` is the Wayland compositor, in kiosk mode: one fullscreen
         surface, no decorations. It starts once a DRM card exists.
      3. `cog` is the WPE WebKit browser, pointed at this app over loopback
         (`url/0`). It starts once the Wayland socket exists.

    The strategy is `:rest_for_one`: if Weston dies, Cog is restarted with it,
    while a Cog crash restarts only Cog. The endpoint is untouched by any of
    this. It still listens on every interface, so the app is reachable over
    the network exactly as on any other target.

    Myelin rides along with Cog as a WPE web process extension. It injects the
    scripts enabled in `config/kiosk.exs` (the screensaver) into every page,
    and those talk to the LiveView through `"myelin:..."` events.
    """

    use Supervisor

    alias HelloLiveView.Kiosk.Udevd

    @runtime_dir "/run"
    @wayland_display "wayland-1"
    @drm_dir "/dev/dri"
    @poll_ms 500
    @max_polls 20

    def start_link(args) do
      Supervisor.start_link(__MODULE__, args, name: __MODULE__)
    end

    @doc """
    The URL Cog opens at boot: this application, over loopback.

    Read from the endpoint's HTTP port so the two cannot drift apart.
    """
    @spec url() :: String.t()
    def url do
      port =
        :hello_live_view
        |> Application.get_env(HelloLiveViewWeb.Endpoint, [])
        |> get_in([:http, :port])

      case port do
        port when port in [nil, 80] -> "http://localhost/"
        port -> "http://localhost:#{port}/"
      end
    end

    @impl true
    def init(_args) do
      children = [
        Udevd,
        Supervisor.child_spec(
          {MuonTrap.Daemon,
           [
             "weston",
             ["--shell=kiosk", "--continue-without-input"],
             [
               env: [{"XDG_RUNTIME_DIR", @runtime_dir}],
               stderr_to_stdout: true,
               log_output: :info,
               log_prefix: "weston: ",
               wait_for: &wait_for_drm_card/0
             ]
           ]},
          id: :weston
        ),
        Supervisor.child_spec(
          {MuonTrap.Daemon,
           [
             "cog",
             ["--platform=wl", url()] ++ Myelin.browser_args(),
             [
               env: cog_env(),
               stderr_to_stdout: true,
               log_output: :info,
               log_prefix: "cog: ",
               wait_for: fn -> wait_for_path(Path.join(@runtime_dir, @wayland_display)) end
             ]
           ]},
          id: :cog
        )
      ]

      Supervisor.init(children, strategy: :rest_for_one)
    end

    defp cog_env do
      [
        {"XDG_RUNTIME_DIR", @runtime_dir},
        {"WAYLAND_DISPLAY", @wayland_display}
      ] ++ Myelin.browser_env()
    end

    # Weston needs a GPU. udevd has usually created the card by now, but on a
    # slow boot it may still be settling.
    defp wait_for_drm_card(polls \\ @max_polls)

    defp wait_for_drm_card(0), do: raise("no DRM card appeared in #{@drm_dir}")

    defp wait_for_drm_card(polls) do
      with {:ok, files} <- File.ls(@drm_dir),
           true <- Enum.any?(files, &drm_card?/1) do
        :ok
      else
        _ ->
          Process.sleep(@poll_ms)
          wait_for_drm_card(polls - 1)
      end
    end

    defp drm_card?("card" <> <<digit>>) when digit in ?0..?9, do: true
    defp drm_card?(_), do: false

    defp wait_for_path(path, polls \\ @max_polls)

    defp wait_for_path(path, 0), do: raise("#{path} did not appear in time")

    defp wait_for_path(path, polls) do
      if File.exists?(path) do
        :ok
      else
        Process.sleep(@poll_ms)
        wait_for_path(path, polls - 1)
      end
    end
  end
end
