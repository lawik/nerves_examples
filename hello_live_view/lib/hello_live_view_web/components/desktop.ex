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

  alias Phoenix.LiveView.JS

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
  # A zoomed window fills the desktop but for this much on every side, so the
  # desktop, and whatever is behind, can still be reached.
  @zoom_margin 16

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
        (@window.zoomed? or @window.h) && "be-window--sized",
        @class
      ]}
      style={window_style(@window, @width)}
      data-x={@window.x}
      data-y={@window.y}
      data-zoomed={to_string(@window.zoomed?)}
      phx-hook="WindowFrame"
      phx-click="focus"
      phx-value-id={@id}
      aria-label={@title}
      {@rest}
    >
      <div class="be-window__tabs" data-drag-handle>
        <div class="be-tab">
          <button
            type="button"
            class="be-tab__button be-tab__button--close"
            phx-click="close"
            phx-value-id={@id}
            title={"Close #{@title}"}
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
        <div class="be-window__resize" data-resize-handle title="Resize"></div>
      </div>
    </section>
    """
  end

  # A zoomed window fills the desktop, a margin all round. The desktop's size
  # is only known in the browser, so the geometry is in its units.
  defp window_style(%{zoomed?: true} = window, _width) do
    inset = "#{@zoom_margin}px"
    span = "calc(100% - #{2 * @zoom_margin}px)"

    "transform: translate3d(#{inset}, #{inset}, 0); z-index: #{window.z}; width: #{span}; height: #{span};"
  end

  defp window_style(window, width),
    do:
      "transform: translate3d(#{window.x}px, #{window.y}px, 0); z-index: #{window.z};#{size_style(window, width)}"

  # Width falls back to the per-window default until someone resizes it; height
  # stays auto so a window fits its content until it is given a size.
  defp size_style(window, default_width) do
    width = if(w = window.w || default_width, do: " width: #{w}px;", else: "")
    height = if window.h, do: " height: #{window.h}px;", else: ""
    width <> height
  end

  @doc """
  A sortable column heading for a Tracker-style list.

  `sort` is the window's current `{column, direction}`. Clicking re-sorts;
  clicking the active column flips direction. `event` is the LiveView event to
  push, so each window keeps its own sort state:

      <.column_header sort={@process_sort} column={:memory} label="Memory"
                      event="sort_processes" numeric />

  `aria-sort` tells a screen reader what the arrow says.
  """
  attr :sort, :any, required: true, doc: "{column, :asc | :desc}"
  attr :column, :atom, required: true
  attr :label, :string, required: true
  attr :event, :string, required: true
  attr :numeric, :boolean, default: false

  def column_header(assigns) do
    {active, direction} = assigns.sort
    assigns = assign(assigns, active?: active == assigns.column, direction: direction)

    ~H"""
    <th
      class={@numeric && "be-table__num"}
      aria-sort={
        cond do
          not @active? -> "none"
          @direction == :asc -> "ascending"
          true -> "descending"
        end
      }
    >
      <button type="button" phx-click={@event} phx-value-by={@column}>
        {@label}<span :if={@active?} aria-hidden="true">{if @direction == :asc, do: "▲", else: "▼"}</span>
      </button>
    </th>
    """
  end

  @doc """
  A menu bar entry.

  Renders as a button so it can carry a `phx-click` and be reached from the
  keyboard:

      <.menu_item phx-click="rescan" phx-value-id="network">Rescan</.menu_item>

  With no handler attached it is inert, and looks the part. As a submit
  button it can drive a form elsewhere in the window through `form`:

      <.menu_item type="submit" form="notes-form">Save</.menu_item>
  """
  attr :type, :string, default: "button", values: ~w(button submit)
  attr :rest, :global, include: ~w(disabled form)
  slot :inner_block, required: true

  def menu_item(assigns) do
    ~H"""
    <button type={@type} class="be-menu-item" {@rest}>{render_slot(@inner_block)}</button>
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

  The logo is the leaf: clicking it drops the Be menu, with About This System
  and, as on the original, Restart and Shut Down. Opening and closing the menu
  is done in the browser with `Phoenix.LiveView.JS`; only a pick reaches the
  server, as `open` or `power`.
  """
  attr :now, :any, default: nil, doc: "a NaiveDateTime, or nil before the socket connects"
  attr :title, :string, default: nil, doc: "hostname and firmware nickname, next to the logo"
  attr :apps, :list, default: [], doc: "one entry per running window"
  attr :focused, :any, default: nil, doc: "id of the window on top, highlighted in the tray"

  def deskbar(assigns) do
    ~H"""
    <header class="be-deskbar">
      <div class="be-deskbar__leaf" phx-click-away={JS.hide(to: "#deskbar-menu")}>
        <button
          type="button"
          class="be-deskbar__leaf-button"
          phx-click={JS.toggle(to: "#deskbar-menu")}
          aria-haspopup="menu"
          aria-controls="deskbar-menu"
        >
          <.nerves_logo size={20} />
          <span :if={@title} class="be-deskbar__title">{@title}</span>
        </button>

        <div id="deskbar-menu" class="be-dropdown hidden" role="menu" aria-label="Be menu">
          <button
            type="button"
            role="menuitem"
            class="be-dropdown__item"
            phx-click={pick(JS.push("open", value: %{id: "system"}))}
          >
            About This System…
          </button>
          <hr class="be-dropdown__separator" />
          <button
            type="button"
            role="menuitem"
            class="be-dropdown__item"
            phx-click={pick(JS.push("power", value: %{id: "power-restart"}))}
          >
            Restart…
          </button>
          <button
            type="button"
            role="menuitem"
            class="be-dropdown__item"
            phx-click={pick(JS.push("power", value: %{id: "power-shut-down"}))}
          >
            Shut Down…
          </button>
        </div>
      </div>

      <nav
        :if={@apps != []}
        class="be-deskbar__tray"
        aria-label="Running windows"
        phx-click-away={JS.hide(to: "#deskbar-windows")}
      >
        <%!-- Room for every window on a wide screen... --%>
        <button
          :for={app <- @apps}
          type="button"
          class="be-deskbar__app hidden sm:inline-flex"
          phx-click="open"
          phx-value-id={app.id}
          aria-pressed={to_string(app.id == @focused)}
        >
          <.haiku_icon name={app.icon} size={16} />
          <span>{app.title}</span>
        </button>

        <%!-- ...and on a phone, the one on top, with the rest behind it. --%>
        <div class="be-deskbar__fold sm:hidden">
          <button
            type="button"
            class="be-deskbar__app"
            phx-click={JS.toggle(to: "#deskbar-windows")}
            aria-haspopup="menu"
            aria-controls="deskbar-windows"
          >
            <.haiku_icon name={focused_app(@apps, @focused).icon} size={16} />
            <span class="be-deskbar__app-title">{focused_app(@apps, @focused).title}</span>
            <span aria-hidden="true">▾</span>
          </button>

          <div id="deskbar-windows" class="be-dropdown be-dropdown--right hidden" role="menu">
            <button
              :for={app <- @apps}
              type="button"
              role="menuitem"
              class="be-dropdown__item be-dropdown__item--window"
              phx-click={JS.hide(to: "#deskbar-windows") |> JS.push("open", value: %{id: app.id})}
              aria-current={to_string(app.id == @focused)}
            >
              <.haiku_icon name={app.icon} size={16} />
              <span>{app.title}</span>
            </button>
          </div>
        </div>
      </nav>

      <div class="be-deskbar__clock">
        <strong>{if @now, do: Calendar.strftime(@now, "%H:%M:%S"), else: "--:--:--"}</strong>
        <span>{if @now, do: Calendar.strftime(@now, "%a %d %b"), else: "UTC"}</span>
      </div>
    </header>
    """
  end

  # A menu pick closes the menu on its way to the server.
  defp pick(js), do: JS.hide(js, to: "#deskbar-menu")

  # The tray names the window on top; with none on top yet, the first.
  defp focused_app(apps, focused), do: Enum.find(apps, hd(apps), &(&1.id == focused))
end
