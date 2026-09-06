defmodule HelloLiveView.I2CTest do
  use ExUnit.Case, async: true

  alias HelloLiveView.I2C

  test "scan/0 lists every bus with what answered on it" do
    scan = I2C.scan()

    assert scan.simulated?
    assert scan.devices >= 2

    assert %{devices: [%{address: 0x10, hex: "0x10"}], error: nil} =
             Enum.find(scan.buses, &(&1.name == "i2c-test-0"))

    assert %{devices: [%{address: 0x20, hex: "0x20"}], error: nil} =
             Enum.find(scan.buses, &(&1.name == "i2c-test-1"))
  end
end
