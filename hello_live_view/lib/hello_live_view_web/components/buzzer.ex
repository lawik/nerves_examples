# Only on the reComputer R22xx target, with HelloLiveView.Buzzer; see
# config/config.exs. The desktop imports it where it renders the window.
if Application.compile_env(:hello_live_view, :buzzer, false) do
  defmodule HelloLiveViewWeb.Components.Buzzer do
    @moduledoc """
    The body of the Buzzer window: beeps, patterns, a hold switch and a line of
    Morse code, for the reComputer R22xx's beeper.

    Stateless. The LiveView plays through `HelloLiveView.Buzzer` and hands
    down what is sounding.
    """
    use Phoenix.Component

    attr :buzzer, :map, default: nil, doc: "the LiveView's :buzzer assign, nil while looking"
    attr :beeps, :list, default: [], doc: "HelloLiveView.Buzzer.beeps()"
    attr :patterns, :list, default: [], doc: "HelloLiveView.Buzzer.patterns()"

    def buzzer_panel(%{buzzer: nil} = assigns) do
      ~H"""
      <p class="p-4 text-center text-be-ink-soft">Looking for the buzzer…</p>
      """
    end

    def buzzer_panel(%{buzzer: %{available?: false}} = assigns) do
      ~H"""
      <p class="p-4 text-center text-be-ink-soft">
        There is no buzzer to play here. On a Seeed reComputer R22xx this drives
        the board's beeper through the <span class="be-mono">recomputer_r22</span>
        library, which only ships on that target.
      </p>
      """
    end

    def buzzer_panel(assigns) do
      ~H"""
      <div class="be-doc mb-3">
        <div class="be-row items-baseline">
          <span class="font-bold">Beep</span>
          <span class="ml-auto text-be-ink-soft">one beep, then silence</span>
        </div>
        <div class="be-row flex-wrap gap-2">
          <button
            :for={beep <- @beeps}
            type="button"
            class="be-btn"
            phx-click="buzzer_beep"
            phx-value-id={beep.id}
          >
            {beep.label} <span class="be-mono text-be-ink-soft">{beep.ms} ms</span>
          </button>
        </div>
      </div>

      <div class="be-doc mb-3">
        <div class="be-row items-baseline">
          <span class="font-bold">Pattern</span>
          <span class="ml-auto text-be-ink-soft">a few beeps in a row</span>
        </div>
        <div class="be-row flex-wrap gap-2">
          <button
            :for={pattern <- @patterns}
            type="button"
            class={["be-btn", playing?(@buzzer, pattern.id) && "be-btn--default"]}
            phx-click="buzzer_play"
            phx-value-id={pattern.id}
          >
            {pattern.label}
          </button>
        </div>
      </div>

      <form class="be-doc mb-3" phx-submit="buzzer_morse">
        <div class="be-row items-baseline">
          <label for="buzzer-morse" class="font-bold">Morse</label>
          <span class="ml-auto text-be-ink-soft">letters, digits and a little punctuation</span>
        </div>
        <div class="be-row gap-2">
          <input
            id="buzzer-morse"
            class="be-input w-full"
            type="text"
            name="text"
            placeholder="SOS"
            maxlength={@buzzer.max_morse}
            autocomplete="off"
            spellcheck="false"
          />
          <button type="submit" class="be-btn">Send</button>
        </div>
      </form>

      <div class="flex flex-wrap items-center gap-x-3 gap-y-1 text-[12px]">
        <button
          type="button"
          class={["be-btn", @buzzer.held? && "be-btn--default"]}
          phx-click="buzzer_hold"
          aria-pressed={to_string(@buzzer.held?)}
        >
          {if @buzzer.held?, do: "Release", else: "Hold on"}
        </button>
        <span :if={@buzzer.held?} class="be-tag be-tag--warn">sounding</span>
        <span :if={@buzzer.playing} class="be-tag be-tag--ok normal-case">
          playing {@buzzer.playing.label}
        </span>
        <span :if={@buzzer.notice} class="be-tag be-tag--warn normal-case">{@buzzer.notice}</span>
        <button type="button" class="be-btn ml-auto" phx-click="buzzer_stop">Stop</button>
      </div>
      """
    end

    defp playing?(%{playing: %{id: id}}, id), do: true
    defp playing?(_buzzer, _id), do: false
  end
end
