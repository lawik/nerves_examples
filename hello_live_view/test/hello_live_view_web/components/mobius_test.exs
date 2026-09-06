defmodule HelloLiveViewWeb.Components.MobiusTest do
  use ExUnit.Case, async: true

  alias HelloLiveViewWeb.Components.Mobius

  doctest Mobius

  test "points/3 places samples by time and scales them to the box" do
    assert Mobius.points([], 0, 100) == ""

    # The first sample sits on the left at the bottom, the last on the right
    # at the top, and the one in between halfway in both.
    assert Mobius.points([{0, 1}, {50, 2}, {100, 3}], 0, 100) == "0.0,28.5 50.0,15.0 100.0,1.5"

    # A flat line sits mid-height rather than dividing by zero.
    assert Mobius.points([{0, 5}, {100, 5}], 0, 100) == "0.0,15.0 100.0,15.0"

    # A sample outside the range is pinned to its edge.
    assert Mobius.points([{-10, 1}, {200, 2}], 0, 100) == "0.0,28.5 100.0,1.5"

    # The line starts at the first sample, not at the start of the range.
    assert Mobius.points([{60, 1}, {80, 2}, {100, 3}], 0, 100) == "0.0,28.5 50.0,15.0 100.0,1.5"
  end

  test "rects/1 gives one bar per bin, standing on the bottom edge and scaled to the tallest" do
    assert Mobius.rects([]) == []

    assert Mobius.rects([{1.0, 3}, {2.0, 1}]) == [
             {"0.3", "1.5", "49.4", "28.5"},
             {"50.3", "20.5", "49.4", "9.5"}
           ]
  end

  test "value/2 reads at a glance in every unit" do
    assert Mobius.value(1_572_864, :bytes) == "1.5 MB"
    assert Mobius.value(12_345, :count) == "12.3k"
    assert Mobius.value(0.5, :load) == "0.50"
    assert Mobius.value(45.25, :celsius) == "45.3 °C"
    assert Mobius.value(2.345, :milliseconds) == "2.3 ms"
    assert Mobius.value(123.4, :milliseconds) == "123 ms"
    assert Mobius.value(2_500, :milliseconds) == "2.5 s"
  end
end
