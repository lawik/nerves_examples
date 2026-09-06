defmodule HelloLiveViewWeb.Components.Terminal do
  @moduledoc """
  The body of the IEx window: what the session has printed, and a line to
  type the next thing on.

  The output is a LiveView stream, so each chunk IEx prints travels to the
  browser once and the server keeps none of it. The `Terminal` hook in
  `assets/js/app.js` keeps the newest line in view, hands focus to the input
  and remembers what was typed for the arrow keys.
  """
  use Phoenix.Component

  import Phoenix.HTML, only: [raw: 1]

  attr :out, :any, required: true, doc: "the stream of printed chunks, each %{id:, html:}"
  attr :prompt, :string, default: nil, doc: "what IEx is asking for; nil while it is busy"
  attr :shell, :any, default: nil, doc: "the session, or nil once it has ended"

  def terminal(assigns) do
    ~H"""
    <div class="flex h-full min-h-0 flex-col">
      <div class="be-terminal" id="iex-terminal" phx-hook="Terminal">
        <pre class="be-terminal__out" id="iex-out" phx-update="stream" data-terminal-out><span :for={{id, chunk} <- @out} id={id}>{raw(chunk.html)}</span></pre>
        <form :if={@shell} class="be-terminal__line" phx-submit="iex_submit">
          <span class="be-terminal__prompt">{@prompt}</span>
          <input
            class="be-terminal__input"
            type="text"
            name="line"
            autocomplete="off"
            autocapitalize="off"
            spellcheck="false"
            aria-label="IEx input"
          />
        </form>
        <p :if={is_nil(@shell)} class="be-terminal__ended">
          The session has ended. Restart is in the menu.
        </p>
      </div>
    </div>
    """
  end
end
