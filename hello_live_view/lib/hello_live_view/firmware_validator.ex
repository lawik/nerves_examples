defmodule HelloLiveView.FirmwareValidator do
  @moduledoc """
  Validates newly installed firmware once the device can reach the internet.

  Nerves boots a freshly written firmware slot as *unvalidated*. If nothing
  validates it before the next reboot the bootloader falls back to the
  previous slot, which is what saves a device from a broken update. The
  question is what counts as "working". This process answers: being able to
  get back online. If the new firmware brought up networking well enough for
  some interface to report `:internet`, it is kept.

  On boot the process checks `Nerves.Runtime.firmware_valid?/0`. If the
  firmware is already validated there is nothing to do and it exits with
  `:ignore`. Otherwise it subscribes to VintageNet's per-interface connection
  status, checks whether any interface already has internet, and then waits
  for the first interface to reach `:internet`. Validating stops the process;
  it is started `:transient` so the supervisor does not restart it.

  Only started on targets; `Nerves.Runtime` and `VintageNet` do not exist on
  the host.
  """

  use GenServer, restart: :transient

  require Logger

  # Both modules are target-only deps; keep the host build warning-free.
  @compile {:no_warn_undefined, [Nerves.Runtime, VintageNet]}

  @connection_pattern ["interface", :_, "connection"]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    if Nerves.Runtime.firmware_valid?() do
      :ignore
    else
      # Subscribe before looking, so a change between the two is not missed.
      VintageNet.subscribe(@connection_pattern)
      {:ok, %{}, {:continue, :check}}
    end
  end

  @impl true
  def handle_continue(:check, state) do
    case Enum.find(VintageNet.match(@connection_pattern), &internet?/1) do
      {["interface", ifname, "connection"], :internet} ->
        validate(ifname, state)

      nil ->
        Logger.info("[FirmwareValidator] firmware unvalidated, waiting for internet")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(
        {VintageNet, ["interface", ifname, "connection"], _old, :internet, _meta},
        state
      ) do
    validate(ifname, state)
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp internet?({_property, status}), do: status == :internet

  defp validate(ifname, state) do
    case Nerves.Runtime.validate_firmware() do
      :ok ->
        Logger.info("[FirmwareValidator] #{ifname} has internet, firmware validated")
        {:stop, :normal, state}

      {:error, reason} ->
        # Stay subscribed; the next interface to come online triggers a retry.
        Logger.error("[FirmwareValidator] validation failed: #{inspect(reason)}")
        {:noreply, state}
    end
  end
end
