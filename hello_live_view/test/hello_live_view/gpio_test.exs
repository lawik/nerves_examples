defmodule HelloLiveView.GPIOTest do
  # The stub backend's 64 lines are shared by every process on the node.
  use ExUnit.Case, async: false

  alias HelloLiveView.GPIO

  # The desktop's own tests use the first pair; these use the second.
  defp pair do
    lines = GPIO.list()
    {Enum.at(lines, 2), Enum.at(lines, 3)}
  end

  test "list/0 names every line, sorted, with an id a click can send back" do
    lines = GPIO.list()

    assert length(lines) == 64
    assert lines == Enum.sort_by(lines, & &1.location)
    assert %{id: "gpiochip0-0", name: "pair_0_0", free?: true, consumer: nil} = hd(lines)
    assert {:ok, %{location: {"gpiochip0", 0}}} = GPIO.fetch("gpiochip0-0")
    assert GPIO.fetch("gpiochip9-99") == :error
  end

  test "the host runs the stub backend" do
    assert GPIO.simulated?()
  end

  test "an output drives the input it is wired to, and the change is reported" do
    {a, b} = pair()

    {:ok, out} = GPIO.open(a)
    {:ok, inp} = GPIO.open(b)
    on_exit(fn -> Enum.each([out, inp], &GPIO.close/1) end)

    assert inp.direction == :input
    assert inp.value == 0

    {:ok, out} = GPIO.set_direction(out, :output)
    assert out.value == 0

    {:ok, out} = GPIO.write(out, 1)
    assert out.value == 1
    assert GPIO.refresh(inp).value == 1

    # The input's subscription is tagged with its id, so the notification
    # can be folded straight into the open lines.
    assert_receive {:circuits_gpio, %{ref: ref, value: 1} = change}
    assert ref == b.id
    opens = GPIO.on_change(%{b.id => inp}, change)
    assert opens[b.id].value == 1
  end

  test "an input cannot be written and an output cannot be pulled" do
    {a, _b} = pair()
    {:ok, open} = GPIO.open(a)
    on_exit(fn -> GPIO.close(open) end)

    assert GPIO.write(open, 1) == {:error, :not_an_output}
    {:ok, output} = GPIO.set_direction(open, :output)
    assert GPIO.set_pull(output, :pullup) == {:error, :not_an_input}
  end

  # The stub backend reports the holder but, unlike real hardware, still lets
  # a second open through, so only the report is checked here.
  test "a line held elsewhere is reported as in use" do
    {a, _b} = pair()
    {:ok, open} = GPIO.open(a)
    on_exit(fn -> GPIO.close(open) end)

    {:ok, line} = GPIO.fetch(a.id)
    refute line.free?
    assert line.consumer == "stub"
  end

  test "names on the wire are parsed without creating atoms" do
    assert GPIO.direction("input") == {:ok, :input}
    assert GPIO.direction("sideways") == :error
    assert GPIO.pull("pulldown") == {:ok, :pulldown}
    assert GPIO.pull("hard") == :error
    assert GPIO.level("1") == {:ok, 1}
    assert GPIO.level("high") == :error
  end
end
