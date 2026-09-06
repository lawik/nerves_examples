defmodule HelloLiveView.I2C do
  @moduledoc """
  What is attached to the device's I2C buses, in a shape the desktop can show.

  A scan asks every bus for every address a device may have, 0x03 to 0x77,
  the way `i2cdetect` does. Whatever answers is listed with a guess at what it
  might be, taken from the addresses the common breakout boards ship with. A
  guess is a hint for the person at the screen; nothing here acts on it.

  Scanning touches every address on a bus, so it happens when the window
  opens and on request, never on a timer.

  On the host there is no I2C hardware and `Circuits.I2C` builds a test
  backend: three fake buses with one device answering on each.
  `simulated?/0` says when that is the case.
  """

  alias Circuits.I2C

  @type address :: 0x03..0x77
  @type device :: %{address: address(), hex: String.t(), guesses: [String.t()]}
  @type bus :: %{name: String.t(), devices: [device()], error: String.t() | nil}
  @type scan :: %{buses: [bus()], devices: non_neg_integer(), simulated?: boolean()}

  # The usual suspects, by the addresses their breakout boards default to.
  # Broad ranges (an EEPROM can sit anywhere in 0x50..0x57) come after the
  # parts pinned to one address, so the likelier name is read first.
  @guesses [
    {0x0C..0x0F, "AK8963 magnetometer"},
    {0x18..0x19, "LIS3DH accelerometer"},
    {0x18..0x1F, "MCP9808 temperature sensor"},
    {0x1A, "WM8731 audio codec"},
    {0x1C..0x1D, "MMA8451 accelerometer"},
    {0x1E, "HMC5883L magnetometer"},
    {0x23, "BH1750 light sensor"},
    {0x24, "PN532 NFC reader"},
    {0x20..0x27, "MCP23017 / PCF8574 I/O expander"},
    {0x28..0x29, "BNO055 IMU"},
    {0x29, "VL53L0X distance sensor"},
    {0x29, "TCS34725 colour sensor"},
    {0x38, "AHT20 humidity sensor"},
    {0x38, "FT6206 touch controller"},
    {0x39, "APDS-9960 gesture sensor"},
    {0x39, "TSL2561 light sensor"},
    {0x3C..0x3D, "SSD1306 OLED display"},
    {0x40, "PCA9685 PWM driver"},
    {0x40, "Si7021 / HTU21D humidity sensor"},
    {0x40..0x4F, "INA219 current sensor"},
    {0x42, "u-blox GPS"},
    {0x44..0x45, "SHT31 humidity sensor"},
    {0x48, "PCF8591 ADC/DAC"},
    {0x48..0x4B, "ADS1115 ADC"},
    {0x48..0x4F, "LM75 / TMP102 temperature sensor"},
    {0x50, "HDMI EDID"},
    {0x53, "ADXL345 accelerometer"},
    {0x50..0x57, "24Cxx EEPROM"},
    {0x5A, "MLX90614 IR thermometer"},
    {0x5A..0x5B, "CCS811 air quality sensor"},
    {0x5A..0x5D, "MPR121 touch controller"},
    {0x5C, "AM2320 humidity sensor"},
    {0x60, "MCP4725 DAC"},
    {0x60, "Si5351 clock generator"},
    {0x60, "ATECC608 secure element"},
    {0x62, "SCD4x CO2 sensor"},
    {0x68, "DS3231 / DS1307 RTC"},
    {0x68, "PCF8523 RTC"},
    {0x68..0x69, "MPU-6050 / MPU-9250 IMU"},
    {0x6A..0x6B, "LSM6DS3 IMU"},
    {0x76..0x77, "BME280 / BMP280 pressure sensor"},
    {0x76..0x77, "BME680 environmental sensor"},
    {0x77, "BMP180 pressure sensor"},
    {0x70..0x77, "TCA9548A I2C multiplexer"},
    {0x70..0x77, "HT16K33 LED driver"}
  ]

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

  @doc "The parts commonly found at an address, likeliest first."
  @spec guesses(address()) :: [String.t()]
  def guesses(address) do
    for {addresses, part} <- @guesses, matches?(addresses, address), do: part
  end

  defp matches?(%Range{} = range, address), do: address in range
  defp matches?(single, address), do: single == address

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
    %{address: address, hex: "0x" <> hex, guesses: guesses(address)}
  end
end
