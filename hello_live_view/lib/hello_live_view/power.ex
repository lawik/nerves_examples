defmodule HelloLiveView.Power do
  @moduledoc """
  Restart or shut down the device, from the Deskbar's leaf menu.

  Both go through `Nerves.Runtime`, which stops the applications in order
  and then hands over to the kernel. Those calls never return, so they run
  in a process of their own and the caller gets `:ok` back at once. The
  node, and this desktop with it, goes away a moment later.

  `Nerves.Runtime` is only compiled into a firmware build. On the host there
  is no device, and both functions say so rather than stopping the dev
  server.
  """

  @type action :: :restart | :shut_down

  @doc "Reboot the device. `{:error, :host}` when there is no device."
  @spec restart() :: :ok | {:error, :host}
  def restart, do: run(:reboot)

  @doc "Power the device off. `{:error, :host}` when there is no device."
  @spec shut_down() :: :ok | {:error, :host}
  def shut_down, do: run(:poweroff)

  @doc "Whether there is a device to restart or shut down."
  @spec available?() :: boolean()
  def available? do
    Code.ensure_loaded?(Nerves.Runtime) and function_exported?(Nerves.Runtime, :reboot, 0)
  end

  defp run(command) do
    if available?() do
      # The call sleeps until the system is down; that is not this process's job.
      _ = spawn(fn -> apply(Nerves.Runtime, command, []) end)
      :ok
    else
      {:error, :host}
    end
  end
end
