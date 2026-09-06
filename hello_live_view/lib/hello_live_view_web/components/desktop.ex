defmodule HelloLiveViewWeb.Components.Desktop do
  @moduledoc """
  BeOS-flavoured desktop chrome: the Deskbar, Tracker-style windows and the
  desktop icons that open them.

  Every component here is stateless — a function component that renders exactly
  what it is handed. Position, stacking and open/closed all live in the
  LiveView's assigns, backed by `HelloLiveView.Windows`, so these functions can
  be reasoned about (and tested) without a socket.

  Visuals live in `assets/css/app.css` under the `.be-*` classes. The icons come
  from the Haiku OS icon theme vendored in `priv/static/images/haiku` — see the
  README there for attribution and how to add more.
  """
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: HelloLiveViewWeb.Endpoint,
    router: HelloLiveViewWeb.Router,
    statics: HelloLiveViewWeb.static_paths()

  @doc """
  Renders one of the vendored Haiku icons.

      <.haiku_icon name="drive-harddisk" size={32} />
  """
  attr :name, :string, required: true, doc: "file name in priv/static/images/haiku, without .svg"
  attr :size, :integer, default: 24
  attr :alt, :string, default: ""
  attr :class, :string, default: nil

  def haiku_icon(assigns) do
    ~H"""
    <img
      src={~p"/images/haiku/#{@name <> ".svg"}"}
      alt={@alt}
      width={@size}
      height={@size}
      class={@class}
      style={"width: #{@size}px; height: #{@size}px;"}
    />
    """
  end

  @doc """
  The Nerves logo in its standard two blues, inlined from the official
  `Nerves Icon.svg` in the branding kit so it needs no extra request.

      <.nerves_logo size={20} />
  """
  attr :size, :integer, default: 20, doc: "height in px; width follows the icon's aspect"
  attr :class, :string, default: nil

  def nerves_logo(assigns) do
    ~H"""
    <svg
      viewBox="0 0 187.98 152.5"
      height={@size}
      width={round(@size * 187.98 / 152.5)}
      class={@class}
      role="img"
      aria-label="Nerves"
      xmlns="http://www.w3.org/2000/svg"
    >
      <title>Nerves</title>
      <path
        fill="#33647E"
        d="M44.97,0h-36C4.02,0,0,4.02,0,8.97v134.57c0,4.95,4.01,8.97,8.97,8.97h30.01c4.95,0,8.97-4.01,8.97-8.97v-5.39c0-4.95-4.01-8.97-8.97-8.97h-6.69c-4.95,0-8.97-4.01-8.97-8.97V32.29c0-4.95,4.01-8.97,8.97-8.97h6.34c1.89,0,3.73,0.6,5.26,1.7l83.13,60.19c5.93,4.29,14.23,0.06,14.23-7.26v-3.83c0-2.83-1.34-5.49-3.6-7.19L50.33,1.78C48.78,0.63,46.9,0,44.97,0z"
      />
      <path
        fill="#42A7C6"
        d="M143.01,152.5h36c4.95,0,8.97-4.01,8.97-8.97V8.97c0-4.95-4.01-8.97-8.97-8.97H149c-4.95,0-8.97,4.01-8.97,8.97v5.39c0,4.95,4.01,8.97,8.97,8.97h6.69c4.95,0,8.97,4.01,8.97,8.97v87.91c0,4.95-4.01,8.97-8.97,8.97h-6.34c-1.89,0-3.73-0.6-5.26-1.7L60.96,67.28c-5.93-4.29-14.23-0.06-14.23,7.26v3.83c0,2.83,1.34,5.49,3.6,7.19l87.31,65.17C139.2,151.88,141.08,152.5,143.01,152.5z"
      />
    </svg>
    """
  end

  @doc """
  A BeOS window: slanted yellow tab, close and zoom boxes, optional menu bar
  and a resize grip in the corner.

  `window` is the persisted state — `%{x:, y:, z:, zoomed?:}`. Position and
  stacking are rendered as an inline `transform` and `z-index` so the first
  paint is already correct; the `WindowDrag` hook only takes over while a drag
  is actually in flight, and hands the final coordinate back to the server.

  Drag by the tab strip, the way you would on a real one.
  """
  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :window, :map, required: true, doc: "%{x:, y:, z:, zoomed?:} from HelloLiveView.Windows"
  attr :icon, :string, default: nil
  attr :active, :boolean, default: false
  attr :width, :integer, default: 460
  attr :class, :string, default: nil
  attr :rest, :global

  slot :menu, doc: "menu bar entries, rendered Tracker-style under the tab"
  slot :inner_block, required: true

  def window(assigns) do
    ~H"""
    <section
      id={@id}
      class={[
        "be-window",
        @active && "be-window--active",
        @window.zoomed? && "be-window--zoomed",
        @class
      ]}
      style={window_style(@window, @width)}
      data-x={@window.x}
      data-y={@window.y}
      data-zoomed={to_string(@window.zoomed?)}
      phx-hook="WindowDrag"
      phx-click="focus"
      phx-value-id={@id}
      aria-label={@title}
      {@rest}
    >
      <div class="be-window__tabs" data-drag-handle>
        <div class="be-tab">
          <button
            type="button"
            class="be-tab__button"
            phx-click="close"
            phx-value-id={@id}
            aria-label={"Close #{@title}"}
          />
          <span class="be-tab__title">
            <.haiku_icon :if={@icon} name={@icon} size={15} />
            <span>{@title}</span>
          </span>
          <button
            type="button"
            class="be-tab__button be-tab__button--zoom"
            phx-click="zoom"
            phx-value-id={@id}
            aria-label={"Zoom #{@title}"}
            aria-pressed={to_string(@window.zoomed?)}
          />
        </div>
      </div>

      <div class="be-window__frame">
        <div :if={@menu != []} class="be-window__menu">
          {render_slot(@menu)}
        </div>
        <div class="be-window__body">
          {render_slot(@inner_block)}
        </div>
        <div class="be-window__grip" aria-hidden="true"></div>
      </div>
    </section>
    """
  end

  # A zoomed window pins to the left edge and spans the desktop, keeping its y.
  defp window_style(%{zoomed?: true} = window, _width),
    do: "transform: translate3d(0, #{window.y}px, 0); z-index: #{window.z};"

  defp window_style(window, width),
    do:
      "transform: translate3d(#{window.x}px, #{window.y}px, 0); z-index: #{window.z}; width: #{width}px;"

  @doc """
  A menu bar entry. Decorative — BeOS windows just look wrong without one.
  """
  slot :inner_block, required: true

  def menu_item(assigns) do
    ~H"""
    <span class="be-menu-item">{render_slot(@inner_block)}</span>
    """
  end

  @doc """
  A Tracker icon sitting on the desktop. Clicking it opens (and raises) the
  matching window.
  """
  attr :id, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :open, :boolean, default: false

  def desktop_icon(assigns) do
    ~H"""
    <button
      type="button"
      class="be-icon-tile"
      phx-click="open"
      phx-value-id={@id}
      aria-pressed={to_string(@open)}
    >
      <.haiku_icon name={@icon} size={40} />
      <span>{@label}</span>
    </button>
    """
  end

  @doc """
  The Deskbar. Haiku keeps it in the top-right corner; here it spans the top
  edge, with the Nerves logo on the left, running apps in the tray and a clock
  that ticks straight from the LiveView.
  """
  attr :now, :any, default: nil, doc: "a NaiveDateTime, or nil before the socket connects"
  attr :apps, :list, default: []
  attr :open, :any, default: [], doc: "ids of the currently open windows"

  def deskbar(assigns) do
    ~H"""
    <header class="be-deskbar">
      <div class="be-deskbar__leaf">
        <.nerves_logo size={20} />
      </div>

      <nav class="be-deskbar__tray" aria-label="Windows">
        <button
          :for={app <- @apps}
          type="button"
          class="be-deskbar__app"
          phx-click="open"
          phx-value-id={app.id}
          aria-pressed={to_string(app.id in @open)}
        >
          <.haiku_icon name={app.icon} size={16} />
          <span class="hidden sm:inline">{app.title}</span>
        </button>
      </nav>

      <div class="be-deskbar__clock">
        <strong>{if @now, do: Calendar.strftime(@now, "%H:%M:%S"), else: "--:--:--"}</strong>
        <span>{if @now, do: Calendar.strftime(@now, "%a %d %b"), else: "UTC"}</span>
      </div>
    </header>
    """
  end
end
