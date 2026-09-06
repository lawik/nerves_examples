defmodule HelloLiveViewWeb.Components.GPIO do
  @moduledoc """
  The body of the GPIO window: the lines this view holds, with their controls,
  above every line the device has.

  Stateless, like the rest of the desktop. The LiveView owns the open lines
  (`HelloLiveView.GPIO`) and hands them down; this only lays them out.
  """
  use Phoenix.Component

  @doc """
  The window. `gpio` is nil until the LiveView has read the controllers.
  """
  attr :gpio, :map, default: nil, doc: "%{lines:, simulated?:} from the LiveView"

  attr :open, :map,
    required: true,
    doc: "id => HelloLiveView.GPIO.open(), the lines this view holds"

  attr :notice, :string, default: nil, doc: "why the last action failed"

  def gpio_panel(%{gpio: nil} = assigns) do
    ~H"""
    <p class="p-4 text-center text-be-ink-soft">Looking for GPIO controllers…</p>
    """
  end

  def gpio_panel(assigns) do
    assigns =
      assign(assigns,
        free: Enum.count(assigns.gpio.lines, & &1.free?),
        total: length(assigns.gpio.lines),
        opens: assigns.open |> Map.values() |> Enum.sort_by(& &1.line.location)
      )

    ~H"""
    <div class="mb-2 flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1 text-[12px]">
      <span class="font-semibold">{@free} of {@total} lines free</span>
      <span :if={@gpio.simulated?} class="be-tag be-tag--idle normal-case">
        simulated: lines are wired in pairs
      </span>
      <span :if={@notice} class="be-tag be-tag--warn normal-case">{@notice}</span>
    </div>

    <div :if={@opens != []} class="be-doc mb-3">
      <.open_line :for={open <- @opens} open={open} />
    </div>

    <p :if={@gpio.lines == []} class="p-4 text-center text-be-ink-soft">
      No GPIO controller was found.
    </p>

    <ul :if={@gpio.lines != []} class="be-doc be-list">
      <li :for={line <- @gpio.lines}>
        <button
          type="button"
          class="be-list__row items-center"
          phx-click="gpio_open"
          phx-value-id={line.id}
          disabled={not line.free? or is_map_key(@open, line.id)}
          aria-pressed={to_string(is_map_key(@open, line.id))}
        >
          <span class="min-w-0 flex-1 truncate">
            <span class="font-bold">{line.name}</span>
            <span class="be-mono ml-2 text-be-ink-soft">{line.id}</span>
          </span>
          <.line_tag line={line} open?={is_map_key(@open, line.id)} />
        </button>
      </li>
    </ul>
    """
  end

  attr :line, :map, required: true
  attr :open?, :boolean, required: true

  defp line_tag(%{open?: true} = assigns) do
    ~H"""
    <span class="be-tag be-tag--ok shrink-0">open</span>
    """
  end

  defp line_tag(%{line: %{free?: true}} = assigns) do
    ~H"""
    <span class="be-tag be-tag--idle shrink-0">free</span>
    """
  end

  defp line_tag(assigns) do
    ~H"""
    <span class="be-tag be-tag--warn shrink-0 normal-case">
      in use{if @line.consumer, do: " by #{@line.consumer}"}
    </span>
    """
  end

  # One held line: its level, then direction, and the setting that direction
  # allows, pull for an input and drive for an output.
  attr :open, :map, required: true, doc: "HelloLiveView.GPIO.open()"

  defp open_line(assigns) do
    ~H"""
    <div class="be-row flex-col gap-2" id={"gpio-" <> @open.line.id}>
      <div class="flex w-full flex-wrap items-center gap-x-2 gap-y-1">
        <span class="font-bold">{@open.line.name}</span>
        <span class="be-mono text-be-ink-soft">{@open.line.id}</span>
        <span class={["be-tag", if(@open.value == 1, do: "be-tag--ok", else: "be-tag--idle")]}>
          {if @open.value == 1, do: "high", else: "low"}
        </span>
        <button
          type="button"
          class="be-btn ml-auto"
          phx-click="gpio_close"
          phx-value-id={@open.line.id}
        >
          Release
        </button>
      </div>

      <div class="flex w-full flex-wrap items-center gap-x-4 gap-y-2 text-[12px]">
        <span class="flex items-center gap-1" role="group" aria-label="Direction">
          <.choice
            event="gpio_direction"
            id={@open.line.id}
            name="direction"
            value="input"
            current={@open.direction == :input}
          >
            Input
          </.choice>
          <.choice
            event="gpio_direction"
            id={@open.line.id}
            name="direction"
            value="output"
            current={@open.direction == :output}
          >
            Output
          </.choice>
        </span>

        <span
          :if={@open.direction == :input}
          class="flex items-center gap-1"
          role="group"
          aria-label="Pull"
        >
          <span class="mr-1 text-be-ink-soft">Pull</span>
          <.choice
            event="gpio_pull"
            id={@open.line.id}
            name="pull"
            value="none"
            current={@open.pull == :none}
          >
            None
          </.choice>
          <.choice
            event="gpio_pull"
            id={@open.line.id}
            name="pull"
            value="pullup"
            current={@open.pull == :pullup}
          >
            Up
          </.choice>
          <.choice
            event="gpio_pull"
            id={@open.line.id}
            name="pull"
            value="pulldown"
            current={@open.pull == :pulldown}
          >
            Down
          </.choice>
        </span>

        <span
          :if={@open.direction == :output}
          class="flex items-center gap-1"
          role="group"
          aria-label="Drive"
        >
          <span class="mr-1 text-be-ink-soft">Drive</span>
          <.choice
            event="gpio_write"
            id={@open.line.id}
            name="level"
            value="0"
            current={@open.value == 0}
          >
            Low
          </.choice>
          <.choice
            event="gpio_write"
            id={@open.line.id}
            name="level"
            value="1"
            current={@open.value == 1}
          >
            High
          </.choice>
        </span>
      </div>
    </div>
    """
  end

  # A radio-like button: pressed when it is the current setting.
  attr :event, :string, required: true
  attr :id, :string, required: true, doc: "the line, sent as phx-value-id"
  attr :name, :string, required: true, doc: "the phx-value-* key the event reads"
  attr :value, :string, required: true
  attr :current, :boolean, required: true
  slot :inner_block, required: true

  defp choice(assigns) do
    assigns = assign(assigns, :value_attr, %{"phx-value-#{assigns.name}" => assigns.value})

    ~H"""
    <button
      type="button"
      class="be-btn"
      phx-click={@event}
      phx-value-id={@id}
      aria-pressed={to_string(@current)}
      {@value_attr}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end
end
