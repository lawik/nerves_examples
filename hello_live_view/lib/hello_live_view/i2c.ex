defmodule HelloLiveView.I2C do
  @moduledoc """
  What is attached to the device's I2C buses, in a shape the desktop can show.

  A scan asks every bus for every address a device may have, 0x03 to 0x77,
  the way `i2cdetect` does. Whatever answers is listed by address. Nothing
  here knows what the part at an address is; that is a job for a driver.

  Scanning touches every address on a bus, so it happens when the window
  opens and on request, never on a timer.

  On the host there is no I2C hardware and `Circuits.I2C` builds a test
  backend: three fake buses with one device answering on each.
  `simulated?/0` says when that is the case.
  """

  alias Circuits.I2C

  @type address :: 0x03..0x77
  @type device :: %{address: address(), hex: String.t()}
  @type bus :: %{name: String.t(), devices: [device()], error: String.t() | nil}
  @type scan :: %{buses: [bus()], devices: non_neg_integer(), simulated?: boolean()}

  @doc "Scan every bus for whatever answers."
  @spec scan() :: scan()
  def scan do
    buses = Enum.map(I2C.bus_names(), &scan_bus/1)

    %{
      buses: buses,
      devices: buses |> Enum.map(&length(&1.devices)) |> Enum.sum(),
      simulated?: simulated?()
    }
  end

  @doc "Whether the buses are the test backend's rather than real hardware."
  @spec simulated?() :: boolean()
  def simulated?, do: match?(%{test?: true}, I2C.info())

  defp scan_bus(name) do
    case I2C.detect_devices(name) do
      addresses when is_list(addresses) ->
        %{name: name, devices: Enum.map(addresses, &device/1), error: nil}

      {:error, reason} ->
        %{name: name, devices: [], error: inspect(reason)}
    end
  end

  defp device(address) do
    hex = address |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(2, "0")
    %{address: address, hex: "0x" <> hex}
  end
end
