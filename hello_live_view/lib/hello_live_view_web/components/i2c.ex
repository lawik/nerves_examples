defmodule HelloLiveViewWeb.Components.I2C do
  @moduledoc """
  The body of the I2C window: every bus, and what answered on it.

  Stateless. The LiveView runs the scan (`HelloLiveView.I2C`) when the window
  opens or Rescan is picked, and hands the result down.
  """
  use Phoenix.Component

  attr :scan, :map, default: nil, doc: "HelloLiveView.I2C.scan(), nil until the first scan"
  attr :scanned_at, :any, default: nil, doc: "when the scan ran, as shown on the Deskbar clock"

  def i2c_panel(%{scan: nil} = assigns) do
    ~H"""
    <p class="p-4 text-center text-be-ink-soft">Scanning the I2C buses…</p>
    """
  end

  def i2c_panel(assigns) do
    ~H"""
    <div class="mb-2 flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1 text-[12px]">
      <span class="font-semibold">
        {count(@scan.devices, "device")} on {count(length(@scan.buses), "bus")}
      </span>
      <span :if={@scan.simulated?} class="be-tag be-tag--idle normal-case">
        simulated: one device per bus
      </span>
      <span :if={@scanned_at} class="text-be-ink-soft">
        scanned {Calendar.strftime(@scanned_at, "%H:%M:%S")}
      </span>
    </div>

    <p :if={@scan.buses == []} class="p-4 text-center text-be-ink-soft">
      No I2C bus found. On a Raspberry Pi the pins on the header are <span class="be-mono">i2c-1</span>.
    </p>

    <div :for={bus <- @scan.buses} class="be-doc mb-3 last:mb-0">
      <div class="be-row items-baseline">
        <span class="font-bold">{bus.name}</span>
        <span class="ml-auto text-be-ink-soft">{count(length(bus.devices), "device")}</span>
      </div>

      <div :if={bus.error} class="be-row">
        <span class="be-tag be-tag--warn normal-case">{bus.error}</span>
      </div>

      <p :if={bus.devices == [] and is_nil(bus.error)} class="be-row text-be-ink-soft">
        Nothing answered.
      </p>

      <div :for={device <- bus.devices} class="be-row items-baseline">
        <span class="be-mono font-bold">{device.hex}</span>
        <span class="min-w-0 flex-1">{guess_text(device.guesses)}</span>
      </div>
    </div>
    """
  end

  defp guess_text([]), do: "no common part at this address"
  defp guess_text(guesses), do: "may be a " <> Enum.join(guesses, ", or a ")

  defp count(1, noun), do: "1 #{noun}"
  defp count(n, "bus"), do: "#{n} buses"
  defp count(n, noun), do: "#{n} #{noun}s"
end
