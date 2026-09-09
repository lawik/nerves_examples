# The buzzer only exists on the reComputer R22xx, and the recomputer_r22
# library is a dependency of that target alone (mix.exs). Elsewhere this file
# compiles to nothing and the desktop has no Buzzer window (config/config.exs).
if Application.compile_env(:hello_live_view, :buzzer, false) do
  defmodule HelloLiveView.Buzzer do
    @moduledoc """
    The reComputer R22xx's buzzer, in a shape the desktop can play.

    `RecomputerR22.Buzzer` guards the hardware: it turns the beeper on and off
    and times a single beep. This module adds what a window wants on top of
    that: named beeps, a few patterns, and Morse code for whatever is typed
    in, each played from a process of its own so the LiveView never sleeps.

    A pattern is played as a series of timed beeps rather than on/off pairs.
    Every beep switches itself off, so if the player is killed halfway through
    the buzzer falls silent by itself instead of staying on.

    The library only ships on the `recomputer_r22` target, and so does this
    module. `available?/0` still covers the first seconds after boot, before
    the beeper's input device has appeared.
    """

    @type beep :: %{id: String.t(), label: String.t(), ms: pos_integer()}
    @type pattern :: %{id: String.t(), label: String.t(), steps: [{pos_integer(), pos_integer()}]}

    # A step is {beep for, then wait} in milliseconds.
    @beeps [
      %{id: "short", label: "Short", ms: 60},
      %{id: "beep", label: "Beep", ms: 150},
      %{id: "long", label: "Long", ms: 500}
    ]

    @patterns [
      %{id: "double", label: "Double", steps: [{80, 80}, {80, 0}]},
      %{id: "triple", label: "Triple", steps: [{80, 80}, {80, 80}, {80, 0}]},
      %{id: "alarm", label: "Alarm", steps: List.duplicate({250, 250}, 4)},
      %{id: "startup", label: "Startup", steps: [{60, 40}, {60, 40}, {200, 0}]}
    ]

    # Morse timing, in units of one dit. Slowish, so it can be followed by ear.
    @dit 70
    @dah 3 * @dit
    @letter_gap 3 * @dit
    @word_gap 7 * @dit
    @max_morse 40

    @morse %{
      ?A => ".-",
      ?B => "-...",
      ?C => "-.-.",
      ?D => "-..",
      ?E => ".",
      ?F => "..-.",
      ?G => "--.",
      ?H => "....",
      ?I => "..",
      ?J => ".---",
      ?K => "-.-",
      ?L => ".-..",
      ?M => "--",
      ?N => "-.",
      ?O => "---",
      ?P => ".--.",
      ?Q => "--.-",
      ?R => ".-.",
      ?S => "...",
      ?T => "-",
      ?U => "..-",
      ?V => "...-",
      ?W => ".--",
      ?X => "-..-",
      ?Y => "-.--",
      ?Z => "--..",
      ?0 => "-----",
      ?1 => ".----",
      ?2 => "..---",
      ?3 => "...--",
      ?4 => "....-",
      ?5 => ".....",
      ?6 => "-....",
      ?7 => "--...",
      ?8 => "---..",
      ?9 => "----.",
      ?. => ".-.-.-",
      ?, => "--..--",
      ?? => "..--..",
      ?! => "-.-.--",
      ?/ => "-..-.",
      ?- => "-....-",
      ?@ => ".--.-."
    }

    @doc "Whether there is a buzzer to play: the library's process is running."
    @spec available?() :: boolean()
    def available? do
      Code.ensure_loaded?(RecomputerR22.Buzzer) and is_pid(Process.whereis(RecomputerR22.Buzzer))
    end

    @doc "The single beeps the window offers."
    @spec beeps() :: [beep()]
    def beeps, do: @beeps

    @doc "The patterns the window offers."
    @spec patterns() :: [pattern()]
    def patterns, do: @patterns

    @doc "How much text `morse/1` will take."
    @spec max_morse() :: pos_integer()
    def max_morse, do: @max_morse

    @doc "Look a beep up by the id on the wire."
    @spec fetch_beep(String.t()) :: {:ok, beep()} | :error
    def fetch_beep(id), do: fetch(@beeps, id)

    @doc "Look a pattern up by the id on the wire."
    @spec fetch_pattern(String.t()) :: {:ok, pattern()} | :error
    def fetch_pattern(id), do: fetch(@patterns, id)

    # `RecomputerR22.Buzzer.beep/2` takes the server first, and the duration
    # second, so one argument alone would be taken for the server's name.
    @doc "One beep, switching itself off after `ms`."
    @spec beep(pos_integer()) :: :ok
    def beep(ms) when is_integer(ms) and ms > 0,
      do: RecomputerR22.Buzzer.beep(RecomputerR22.Buzzer, ms)

    @doc "Hold the buzzer on until `off/0`."
    @spec on() :: :ok
    def on, do: RecomputerR22.Buzzer.on()

    @doc "Silence, cancelling any beep in progress."
    @spec off() :: :ok
    def off, do: RecomputerR22.Buzzer.off()

    @doc """
    Play steps from a process of their own. The caller gets `{:buzzer, :done, ref}`
    when the last one has sounded; `stop/1` cuts it short.
    """
    @spec play([{pos_integer(), non_neg_integer()}]) :: {pid(), reference()}
    def play(steps) do
      parent = self()
      ref = make_ref()

      {:ok, pid} =
        Task.start(fn ->
          Enum.each(steps, fn {sound, gap} ->
            beep(sound)
            Process.sleep(sound + gap)
          end)

          send(parent, {:buzzer, :done, ref})
        end)

      {pid, ref}
    end

    @doc "Stop a player started with `play/1` and silence the buzzer."
    @spec stop(pid()) :: :ok
    def stop(pid) do
      Process.exit(pid, :kill)
      off()
    end

    @doc """
    Turn text into steps for `play/1`, or `:error` if there is nothing to send.
    Letters and digits are sent, common punctuation too; anything else is
    skipped. A space is the gap between words.
    """
    @spec morse(String.t()) :: {:ok, [{pos_integer(), non_neg_integer()}]} | :error
    def morse(text) do
      words =
        text
        |> String.slice(0, @max_morse)
        |> String.upcase()
        |> String.split()
        |> Enum.map(&letters/1)
        |> Enum.reject(&(&1 == []))

      case words do
        [] -> :error
        _ -> {:ok, words |> Enum.map(&word_steps/1) |> join_words()}
      end
    end

    defp letters(word) do
      word
      |> String.to_charlist()
      |> Enum.flat_map(fn char ->
        case Map.fetch(@morse, char) do
          {:ok, code} -> [code]
          :error -> []
        end
      end)
    end

    # Within a letter the gap is a dit; between letters, three of them.
    defp word_steps(codes) do
      codes
      |> Enum.map(&letter_steps/1)
      |> Enum.intersperse(:letter_gap)
      |> List.flatten()
      |> close_gaps(@letter_gap)
    end

    defp letter_steps(code) do
      code
      |> String.to_charlist()
      |> Enum.map(fn
        ?. -> {@dit, @dit}
        ?- -> {@dah, @dit}
      end)
    end

    defp join_words(words) do
      words
      |> Enum.intersperse(:word_gap)
      |> List.flatten()
      |> close_gaps(@word_gap)
    end

    # A gap marker replaces the trailing wait of the step before it.
    defp close_gaps(steps, gap) do
      steps
      |> Enum.reduce([], fn
        marker, [{sound, _wait} | rest] when marker in [:letter_gap, :word_gap] ->
          [{sound, gap} | rest]

        {_sound, _wait} = step, acc ->
          [step | acc]
      end)
      |> Enum.reverse()
    end

    defp fetch(list, id) do
      case Enum.find(list, &(&1.id == id)) do
        nil -> :error
        found -> {:ok, found}
      end
    end
  end
end
