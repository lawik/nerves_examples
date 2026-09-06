defmodule HelloLiveView.I2CTest do
  use ExUnit.Case, async: true

  alias HelloLiveView.I2C

  test "scan/0 lists every bus with what answered on it" do
    scan = I2C.scan()

    assert scan.simulated?
    assert scan.devices >= 2

    assert %{devices: [%{address: 0x10, hex: "0x10"}], error: nil} =
             Enum.find(scan.buses, &(&1.name == "i2c-test-0"))

    assert %{devices: [%{address: 0x20, hex: "0x20", guesses: [_ | _]}]} =
             Enum.find(scan.buses, &(&1.name == "i2c-test-1"))
  end

  test "guesses/1 names the usual suspects at an address" do
    assert "DS3231 / DS1307 RTC" in I2C.guesses(0x68)
    assert "MPU-6050 / MPU-9250 IMU" in I2C.guesses(0x69)
    # A part pinned to one address is named before one that could be anywhere.
    assert ["HDMI EDID", "24Cxx EEPROM"] = I2C.guesses(0x50)
    assert I2C.guesses(0x03) == []
  end
end
