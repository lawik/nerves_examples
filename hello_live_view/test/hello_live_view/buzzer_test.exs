# HelloLiveView.Buzzer only compiles on the reComputer R22xx target, so these
# only run when the suite does: `MIX_TARGET=recomputer_r22 mix test`.
if Application.compile_env(:hello_live_view, :buzzer, false) do
  defmodule HelloLiveView.BuzzerTest do
    use ExUnit.Case, async: true

    alias HelloLiveView.Buzzer

    test "available?/0 is false without the reComputer library" do
      refute Buzzer.available?()
    end

    test "morse/1 spaces dits and dahs within, between and across words" do
      assert {:ok, steps} = Buzzer.morse("sos e")

      # S: three dits, then a letter gap; O: three dahs, then a letter gap;
      # S again, then a word gap; E: one dit ending the line.
      assert steps == [
               {70, 70},
               {70, 70},
               {70, 210},
               {210, 70},
               {210, 70},
               {210, 210},
               {70, 70},
               {70, 70},
               {70, 490},
               {70, 70}
             ]
    end

    test "morse/1 skips what it cannot send and refuses an empty line" do
      assert {:ok, [{70, 70}]} = Buzzer.morse("  ~e~  ")
      assert :error = Buzzer.morse("")
      assert :error = Buzzer.morse("   ")
      assert :error = Buzzer.morse("~~~")
    end

    test "morse/1 only takes so much" do
      {:ok, all} = Buzzer.morse(String.duplicate("e", Buzzer.max_morse()))
      {:ok, more} = Buzzer.morse(String.duplicate("e", Buzzer.max_morse() + 10))
      assert length(all) == Buzzer.max_morse()
      assert more == all
    end

    test "beeps and patterns are looked up by id" do
      assert {:ok, %{ms: 150}} = Buzzer.fetch_beep("beep")
      assert :error = Buzzer.fetch_beep("nope")
      assert {:ok, %{steps: [_ | _]}} = Buzzer.fetch_pattern("double")
      assert :error = Buzzer.fetch_pattern("nope")
    end
  end
end
