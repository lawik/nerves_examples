defmodule HelloLiveViewWeb.Home do
  @moduledoc """
  A BeOS-style desktop for the device.

  The LiveView owns all windowing state — which windows are open, where they
  sit and how they stack — and `HelloLiveView.Windows` keeps it in `:dets` under
  `/data` so it survives a reboot. `HelloLiveViewWeb.Components.Desktop.window/1`
  is stateless and just renders what it is given.

  Adding a window means adding an entry to `@apps` and a `<.window>` in
  `render/1`. Placement, stacking, dragging and persistence come for free.
  """
  use HelloLiveViewWeb, :live_view

  alias HelloLiveView.DeviceInfo
  alias HelloLiveView.Windows

  # The window registry: presentation only. Anything persisted lives in
  # HelloLiveView.Windows, keyed by these ids.
  @apps [
    %{
      id: "system",
      title: "About This System",
      label: "About",
      icon: "computer",
      width: 460
    },
    %{
      id: "resources",
      title: "Resources",
      label: "Resources",
      icon: "utilities-system-monitor",
      width: 470
    },
    %{
      id: "network",
      title: "Network",
      label: "Network",
      icon: "network-wireless",
      width: 520
    }
  ]

  # The clock ticks every second; the full snapshot shells out to `free` and
  # `df`, so it refreshes more gently.
  @tick_interval 1_000
  @refresh_interval 5_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(@tick_interval, self(), :tick)
      :timer.send_interval(@refresh_interval, self(), :refresh)
    end

    device = DeviceInfo.read()

    {:ok,
     socket
     |> assign(:page_title, device.hostname)
     |> assign(:apps, @apps)
     |> assign(:device, device)
     |> assign(:now, device.clock.time)
     |> assign_windows(Windows.all())}
  end

  @impl true
  def handle_info(:tick, socket) do
    clock = DeviceInfo.clock()
    device = %{socket.assigns.device | clock: clock, uptime: DeviceInfo.uptime()}

    {:noreply, assign(socket, device: device, now: clock.time)}
  end

  def handle_info(:refresh, socket) do
    {:noreply, assign(socket, :device, DeviceInfo.read())}
  end

  @impl true
  def handle_event("open", %{"id" => id}, socket) do
    {:noreply, assign_windows(socket, Windows.open(id))}
  end

  def handle_event("close", %{"id" => id}, socket) do
    {:noreply, assign_windows(socket, Windows.close(id))}
  end

  def handle_event("focus", %{"id" => id}, socket) do
    {:noreply, assign_windows(socket, Windows.raise_window(id))}
  end

  def handle_event("zoom", %{"id" => id}, socket) do
    {:noreply, assign_windows(socket, Windows.toggle_zoom(id))}
  end

  # Pushed by the WindowDrag hook on pointer-up, with the final coordinate.
  def handle_event("move", %{"id" => id, "x" => x, "y" => y}, socket)
      when is_integer(x) and is_integer(y) do
    {:noreply, assign_windows(socket, Windows.move(id, x, y))}
  end

  # Escape closes the focused window, like any desktop.
  def handle_event("close_top", _params, %{assigns: %{focused: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("close_top", _params, socket) do
    {:noreply, assign_windows(socket, Windows.close(socket.assigns.focused))}
  end

  # Derived once per update so the template never has to reach for it: the
  # window with the highest z is the focused one, exactly as on a real desktop.
  defp assign_windows(socket, windows) do
    open = for {id, w} <- windows, w.open?, do: {id, w}

    socket
    |> assign(:windows, windows)
    |> assign(:open, Enum.map(open, &elem(&1, 0)))
    |> assign(
      :focused,
      open |> Enum.max_by(fn {_id, w} -> w.z end, fn -> {nil, nil} end) |> elem(0)
    )
  end

  # Windows we have no state for yet are simply not open.
  defp placement(windows, id), do: Map.get(windows, id, %{x: 0, y: 0, z: 1, zoomed?: false})

  @impl true
  def render(assigns) do
    ~H"""
    <div id="desktop" class="be-desktop" phx-window-keydown="close_top" phx-key="Escape">
      <aside class="be-desktop__icons" aria-label="Desktop">
        <.desktop_icon
          :for={app <- @apps}
          id={app.id}
          icon={app.icon}
          label={app.label}
          open={app.id in @open}
        />
      </aside>

      <p :if={@open == []} class="be-desktop__empty">
        Nothing open. Double-click is optional — one click on an icon will do.
      </p>

      <.window
        :if={"system" in @open}
        id="system"
        title="About This System"
        icon="computer"
        width={460}
        active={@focused == "system"}
        window={placement(@windows, "system")}
      >
        <:menu>
          <.menu_item>System</.menu_item>
          <.menu_item>View</.menu_item>
        </:menu>

        <div class="flex items-start gap-4">
          <.haiku_icon name={platform_icon(@device.runtime.target)} size={48} />
          <div class="min-w-0">
            <div class="text-[15px] font-bold">
              {@device.firmware.product} {@device.firmware.version}
            </div>
            <div class="be-mono mt-0.5 break-all text-be-ink-soft">
              {@device.firmware.id || "no firmware image — running on the host"}
            </div>
            <div class="mt-2 flex flex-wrap gap-1.5">
              <span class="be-tag">MIX_TARGET {@device.runtime.target}</span>
              <span class={["be-tag", firmware_tag_class(@device.firmware.validity)]}>
                {firmware_label(@device.firmware)}
              </span>
            </div>
          </div>
        </div>

        <hr class="be-divider" />

        <dl class="be-field">
          <dt>Serial</dt>
          <dd class="be-mono break-all">{@device.serial_number || "—"}</dd>
          <dt>Platform</dt>
          <dd class="be-mono break-all">{@device.platform}</dd>
          <dt>Hostname</dt>
          <dd>{@device.hostname}</dd>
          <dt>Clock</dt>
          <dd>
            {@device.clock.time}
            <span :if={not @device.clock.synchronized?} class="be-tag be-tag--warn ml-1">
              unsynchronized
            </span>
          </dd>
          <dt>Uptime</dt>
          <dd>{@device.uptime.text}</dd>
          <dt>Runtime</dt>
          <dd>Elixir {@device.runtime.elixir} · Erlang/OTP {@device.runtime.otp}</dd>
        </dl>
      </.window>

      <.window
        :if={"resources" in @open}
        id="resources"
        title="Resources"
        icon="utilities-system-monitor"
        width={470}
        active={@focused == "resources"}
        window={placement(@windows, "resources")}
      >
        <:menu>
          <.menu_item>View</.menu_item>
          <.menu_item>Settings</.menu_item>
        </:menu>

        <.usage_meter
          :if={match?({:ok, _stats}, @device.memory.system)}
          icon="preferences-system"
          label="Memory usage"
          stats={elem(@device.memory.system, 1)}
        />

        <.usage_meter
          :if={@device.storage}
          icon="drive-harddisk"
          label="Part usage"
          stats={@device.storage}
          note={@device.storage.path}
        />

        <hr class="be-divider" />

        <dl class="be-field">
          <dt>BEAM memory</dt>
          <dd>{format_bytes(@device.memory.beam_bytes)}</dd>
          <dt>Load average</dt>
          <dd class="be-mono">
            {if @device.load_average, do: Enum.join(@device.load_average, "  "), else: "—"}
          </dd>
          <dt>Temperature</dt>
          <dd>{if @device.temperature, do: "#{@device.temperature} °C", else: "—"}</dd>
          <dt>Applications</dt>
          <dd>
            {@device.applications.started} started
            <span
              :if={@device.applications.not_started != []}
              class="be-tag be-tag--warn ml-1 normal-case"
            >
              {Enum.join(@device.applications.not_started, ", ")} not started
            </span>
          </dd>
          <dt>Processes</dt>
          <dd>{@device.runtime.processes} of {@device.runtime.process_limit}</dd>
          <dt>Schedulers</dt>
          <dd>{@device.runtime.schedulers} online</dd>
        </dl>
      </.window>

      <.window
        :if={"network" in @open}
        id="network"
        title="Network"
        icon="network-wireless"
        width={520}
        active={@focused == "network"}
        window={placement(@windows, "network")}
      >
        <:menu>
          <.menu_item>Interfaces</.menu_item>
        </:menu>

        <div class="be-doc">
          <p :if={@device.networks == []} class="p-4 text-center text-be-ink-soft">
            No interfaces are carrying an address.
          </p>

          <div :for={interface <- @device.networks} class="be-row">
            <.haiku_icon name={interface_icon(interface.name)} size={24} />
            <div class="min-w-0 flex-1">
              <div class="flex flex-wrap items-baseline gap-x-2 gap-y-1">
                <span class="text-[13px] font-bold">{interface.name}</span>
                <span class={["be-tag", if(interface.up?, do: "be-tag--ok", else: "be-tag--idle")]}>
                  {if interface.up?, do: "up", else: "down"}
                </span>
                <span :if={interface.hwaddr} class="be-mono text-be-ink-soft">
                  {interface.hwaddr}
                </span>
              </div>
              <ul class="mt-1">
                <li
                  :for={address <- interface.addresses}
                  class="be-mono break-all text-be-ink-soft"
                >
                  {address.text}
                </li>
              </ul>
            </div>
          </div>
        </div>
      </.window>
    </div>
    """
  end

  # A labelled bar for the "N MB of M MB" resources.
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :stats, :map, required: true
  attr :note, :string, default: nil

  defp usage_meter(assigns) do
    ~H"""
    <div class="mb-4 last:mb-0">
      <div class="mb-1 flex items-baseline gap-2">
        <.haiku_icon name={@icon} size={16} />
        <span class="text-[12px] font-semibold">{@label}</span>
        <span class="ml-auto text-[12px] font-semibold tabular-nums">
          {@stats.used_mb} MB of {@stats.size_mb} MB ({@stats.used_percent}%)
        </span>
      </div>
      <div class="be-meter">
        <div
          class={["be-meter__fill", @stats.used_percent >= 85 && "be-meter__fill--warn"]}
          style={"width: #{@stats.used_percent}%"}
        >
        </div>
      </div>
      <p :if={@note} class="be-mono mt-1 truncate text-[10px] text-be-ink-soft" title={@note}>
        {@note}
      </p>
    </div>
    """
  end

  defp platform_icon("host"), do: "computer"
  defp platform_icon(_target), do: "audio-card"

  defp interface_icon("wlan" <> _rest), do: "network-wireless"
  defp interface_icon("usb" <> _rest), do: "media-flash-memory-stick"
  defp interface_icon(_name), do: "network-workgroup"

  defp firmware_tag_class(:valid), do: "be-tag--ok"
  defp firmware_tag_class(:invalid), do: "be-tag--warn"
  defp firmware_tag_class(_unknown), do: "be-tag--idle"

  defp firmware_label(%{validity: :valid, partition: partition}), do: "Valid (#{partition})"

  defp firmware_label(%{validity: :invalid, partition: partition}),
    do: "Not validated (#{partition})"

  defp firmware_label(_firmware), do: "Firmware unknown"

  @kb 1024
  @mb 1024 * @kb
  @gb 1024 * @mb

  defp format_bytes(bytes) when bytes < @kb, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < @mb, do: "#{Float.round(bytes / @kb, 1)} kB"
  defp format_bytes(bytes) when bytes < @gb, do: "#{Float.round(bytes / @mb, 1)} MB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / @gb, 2)} GB"
end
