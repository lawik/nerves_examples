defmodule HelloLiveView.WindowsTest do
  # One table for the whole node, so one test at a time.
  use ExUnit.Case, async: false

  alias HelloLiveView.Windows

  setup do
    Windows.reset()
    on_exit(fn -> Windows.reset() end)
    :ok
  end

  test "fit/2 brings a window inside the viewport and narrows one too wide for it" do
    Windows.open("wide")
    Windows.move("wide", 900, 700)

    %{"wide" => wide} = Windows.fit([{"wide", 460}], {360, 600})

    assert wide.w == 360 - 24
    assert wide.h == nil
    assert wide.x + wide.w <= 360
    assert wide.y + 320 <= 600
  end

  test "fit/2 leaves a window that already fits as it is" do
    Windows.open("small")
    Windows.move("small", 40, 30)

    %{"small" => small} = Windows.fit([{"small", 300}], {1280, 800})

    assert %{x: 40, y: 30, w: nil, h: nil} = small
  end

  test "fit/2 shortens a window that was sized taller than the viewport" do
    Windows.open("tall")
    Windows.resize("tall", 300, 900)

    %{"tall" => tall} = Windows.fit([{"tall", 300}], {800, 500})

    assert tall.h == 500 - 24
    assert tall.y + tall.h <= 500
  end

  test "a window may be moved off the sides but not above the desktop" do
    Windows.open("aside")

    assert %{"aside" => %{x: -200, y: 0}} = Windows.move("aside", -200, -50)
  end
end
