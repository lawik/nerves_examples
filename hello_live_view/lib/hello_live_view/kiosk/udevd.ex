# Kiosk targets only; see HelloLiveView.Kiosk.
if Application.compile_env(:hello_live_view, :kiosk, false) do
  defmodule HelloLiveView.Kiosk.Udevd do
    @moduledoc """
    Runs `udevd` and settles the device tree before the compositor starts.

    Nerves systems do not normally run udev: the kernel's devtmpfs creates the
    device nodes on its own. Weston needs more than the nodes, though. libinput
    asks udev for the seat's input devices and Mesa asks it about the GPU, so
    the kiosk systems ship udevd and something has to start it. This process
    does, then replays the add events for everything already present and waits
    for the queue to drain, so the compositor that follows it sees a complete
    picture.

    The daemon is linked: if udevd exits, this process goes with it and the
    parent's `:rest_for_one` brings the whole stack back up in order.
    """

    use GenServer

    def start_link(args) do
      GenServer.start_link(__MODULE__, args, name: __MODULE__)
    end

    @impl true
    def init(_args) do
      {:ok, daemon} =
        MuonTrap.Daemon.start_link("udevd", [],
          stderr_to_stdout: true,
          log_output: :debug,
          log_prefix: "udevd: "
        )

      udevadm(~w(trigger --type=subsystems --action=add))
      udevadm(~w(trigger --type=devices --action=add))
      udevadm(~w(settle --timeout=30))

      {:ok, %{daemon: daemon}}
    end

    defp udevadm(args) do
      case System.cmd("udevadm", args, stderr_to_stdout: true) do
        {_output, 0} -> :ok
        {output, status} -> raise "udevadm #{Enum.join(args, " ")} failed (#{status}): #{output}"
      end
    end
  end
end
