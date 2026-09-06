defmodule HelloLiveView.PowerTest do
  use ExUnit.Case, async: true

  alias HelloLiveView.Power

  test "on the host there is no device to restart or shut down" do
    refute Power.available?()
    assert Power.restart() == {:error, :host}
    assert Power.shut_down() == {:error, :host}
  end
end
