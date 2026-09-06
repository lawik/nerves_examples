defmodule HelloLiveViewWeb.Home do
  @moduledoc """
  A BeOS-style desktop for the device.

  The LiveView owns all windowing state — which windows are open, where they
  sit and how they stack — and `HelloLiveView.Windows` keeps it in `:dets` under
  `/data` so it survives a reboot. `HelloLiveViewWeb.Components.Desktop.window/1`
  is stateless and just renders what it is given.

  Adding a window means adding an entry to `@apps` and a `<.window>` in
  `render/1`. Placement, stacking, dragging and persistence come for free.

  Application windows are the exception: one opens per OTP application picked
  in the Applications navigator, under the id `app-<name>`. While such a
  window (or the navigator) is open its contents are polled; closing it ends
  the polling and drops the data. The Mobius window is polled the same way,
  re-reading `HelloLiveView.Metrics.history/1` for the range it is showing.

  Files opened from the Files window work much the same way: one editor
  window per file, under an id that encodes the path (`file_window_id/2`),
  and an alert window for a file that has no viewer. Those are read once
  when they open, never polled, and forgotten when they close.

  Restart and Shut Down, from the Deskbar's leaf menu, ask first in a window
  of their own (`power-restart`, `power-shut-down`). Like an alert, that
  question is answered rather than restored.
  """
  use HelloLiveViewWeb, :live_view
  import HelloLiveViewWeb.Format

  require Logger

  alias HelloLiveView.Applications
  alias HelloLiveView.Camera
  alias HelloLiveView.DeviceInfo
  alias HelloLiveView.Files
  alias HelloLiveView.GPIO
  alias HelloLiveView.I2C
  alias HelloLiveView.Metrics
  alias HelloLiveView.Power
  alias HelloLiveView.Processes
  alias HelloLiveView.Shell
  alias HelloLiveView.WiFi
  alias HelloLiveView.Windows
  alias HelloLiveViewWeb.ANSI

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
    },
    %{
      id: "processes",
      title: "Processes",
      label: "Processes",
      icon: "system-run",
      width: 640
    },
    %{
      id: "applications",
      title: "Applications",
      label: "Applications",
      icon: "applications-engineering",
      width: 560
    },
    %{
      id: "gpio",
      title: "GPIO",
      label: "GPIO",
      icon: "input-gaming",
      width: 560
    },
    %{
      id: "files",
      title: "Files",
      label: "Files",
      icon: "system-file-manager",
      width: 620
    },
    %{
      id: "i2c",
      title: "I2C",
      label: "I2C",
      icon: "plugins",
      width: 520
    },
    %{
      id: "iex",
      title: "IEx",
      label: "IEx",
      icon: "terminal",
      width: 640
    },
    %{
      id: "wifi",
      title: "WiFi",
      label: "WiFi",
      icon: "preferences-system-network",
      width: 520
    },
    %{
      id: "mobius",
      title: "Mobius",
      label: "Mobius",
      icon: "office-chart-line",
      width: 600
    },
    %{
      id: "camera",
      title: "Security Camera",
      label: "Camera",
      icon: "camera-video",
      width: 640
    }
  ]

  # Every application window shares this icon.
  @app_icon "application-x-executable"
  # Likewise every editor window, and every "no viewer" alert.
  @editor_icon "accessories-text-editor"
  @alert_icon "dialog-warning"

  # The leaf menu's two questions, one window each so the tray can name them.
  @power_icon "application-exit"
  @power_windows %{
    "power-restart" => %{action: :restart, title: "Restart"},
    "power-shut-down" => %{action: :shut_down, title: "Shut Down"}
  }

  # The clock ticks every second; the full snapshot shells out to `free` and
  # `df`, so it refreshes more gently.
  @tick_interval 1_000
  @refresh_interval 5_000
  # Open application windows poll their own numbers.
  @poll_interval 2_000

  # What the Resources window shows for CPU before the first real reading.
  @no_cpu %{total: nil, cores: []}
  # cpu_sup reads 100% for two calls inside one clock tick; leave at least this
  # long between readings.
  @cpu_min_window 250

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(@tick_interval, self(), :tick)
      :timer.send_interval(@refresh_interval, self(), :refresh)
    end

    device = DeviceInfo.read()

    socket =
      socket
      |> assign(:page_title, DeviceInfo.title(device))
      |> assign(:apps, @apps)
      |> assign(:app_icon, @app_icon)
      |> assign(:editor_icon, @editor_icon)
      |> assign(:alert_icon, @alert_icon)
      |> assign(:power_icon, @power_icon)
      |> assign(:device, device)
      |> assign(:processes, [])
      |> assign(:process_sort, {:memory, :desc})
      |> assign(:selected_process, nil)
      |> assign(:process_status, nil)
      |> assign(:applications, nil)
      |> assign(:app_info, %{})
      |> assign(:app_errors, %{})
      |> assign(:polling, MapSet.new())
      |> assign(:required, Applications.required_by_ui())
      |> assign(:gpio, nil)
      |> assign(:gpio_open, %{})
      |> assign(:gpio_notice, nil)
      |> assign(:i2c, nil)
      |> assign(:i2c_scanned_at, nil)
      |> assign(:wifi, nil)
      |> assign(:camera, nil)
      |> assign(:camera_notice, nil)
      |> assign(:viewport, nil)
      |> assign(:mobius, nil)
      |> assign(:mobius_range, Metrics.default_range())
      |> assign(:mobius_notice, nil)
      |> assign(:mobius_dir, Metrics.persistence_dir())
      |> assign(:files, nil)
      |> assign(:files_new, nil)
      |> assign(:files_notice, nil)
      |> assign(:editors, %{})
      |> assign(:alerts, %{})
      |> assign(:power, nil)
      |> assign(:shell, nil)
      |> assign(:shell_ref, nil)
      |> assign(:prompt, nil)
      |> assign(:term_style, ANSI.initial())
      |> assign(:term_seq, 0)
      |> stream(:out, [])
      |> assign(:now, device.clock.time)
      |> assign(:cpu_supported?, DeviceInfo.cpu_supported?())
      |> assign(:cpu_read_at, nil)
      |> assign(:cpu, @no_cpu)
      |> assign_windows(Windows.all())

    # Windows left open last time pick up where they were.
    socket = Enum.reduce(socket.assigns.open, socket, &restore(&2, &1))
    {:ok, refresh_cpu(socket)}
  end

  @impl true
  def handle_info(:tick, socket) do
    clock = DeviceInfo.clock()
    device = %{socket.assigns.device | clock: clock, uptime: DeviceInfo.uptime()}

    {:noreply,
     socket
     |> assign(device: device, now: clock.time)
     |> refresh_processes()
     |> refresh_cpu()}
  end

  def handle_info(:refresh, socket) do
    {:noreply, assign(socket, :device, DeviceInfo.read())}
  end

  # One poll loop per open polled window. Once the window is closed the loop
  # ends by itself and the data it fed is dropped.
  def handle_info({:poll, id}, socket) do
    if id in socket.assigns.open do
      schedule_poll(id)
      {:noreply, load(socket, id)}
    else
      {:noreply, socket |> update(:polling, &MapSet.delete(&1, id)) |> forget(id)}
    end
  end

  # An input this view holds changed level. Subscriptions are tagged with the
  # line's id, so the notification says which one.
  def handle_info({:circuits_gpio, %{} = change}, socket) do
    {:noreply, update(socket, :gpio_open, &GPIO.on_change(&1, change))}
  end

  # The IEx window's session: what it printed, that it wants a line, that it
  # ended. Anything from a session already replaced is dropped.
  def handle_info({:shell, shell, message}, %{assigns: %{shell: shell}} = socket) do
    case message do
      {:output, text} -> {:noreply, term_write(socket, text)}
      {:prompt, prompt} -> {:noreply, assign(socket, :prompt, prompt)}
      :exit -> {:noreply, assign(socket, shell: nil, shell_ref: nil, prompt: nil)}
    end
  end

  def handle_info({:shell, _old_shell, _message}, socket), do: {:noreply, socket}

  def handle_info({:DOWN, ref, :process, _shell, _reason}, %{assigns: %{shell_ref: ref}} = socket) do
    {:noreply, assign(socket, shell: nil, shell_ref: nil, prompt: nil)}
  end

  # The camera reporting a new still, an error or a stop, while its window
  # is open.
  def handle_info({:camera, status}, %{assigns: %{camera: %{}}} = socket) do
    {:noreply, assign(socket, :camera, status)}
  end

  def handle_info({:camera, _status}, socket), do: {:noreply, socket}

  # VintageNet reporting a change on the WiFi interface while its window is
  # open: a scan finished, or the association or an address changed.
  def handle_info(
        {VintageNet, ["interface", _ifname, "wifi", "access_points"], _old, aps, _meta},
        socket
      ) do
    {:noreply, wifi_update(socket, &%{&1 | networks: WiFi.summarize(aps || []), scanned?: true})}
  end

  def handle_info({VintageNet, ["interface", _ifname | _rest], _old, _new, _meta}, socket) do
    {:noreply, wifi_update(socket, &%{&1 | status: WiFi.status()})}
  end

  @impl true
  # The browser saying how big the desktop is, on connect and whenever that
  # changes. Every open window is made to fit it.
  def handle_event("viewport", %{"w" => w, "h" => h}, socket)
      when is_integer(w) and is_integer(h) and w > 0 and h > 0 do
    fitted = Windows.fit(Enum.map(socket.assigns.open, &{&1, window_width(&1)}), {w, h})
    {:noreply, socket |> assign(:viewport, {w, h}) |> assign_windows(fitted)}
  end

  def handle_event("viewport", _params, socket), do: {:noreply, socket}

  def handle_event("open", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign_windows(open_fitted(id, socket.assigns.viewport))
     |> refresh_processes()
     |> refresh_cpu()
     |> track(id)}
  end

  def handle_event("close", %{"id" => id}, socket) do
    {:noreply, socket |> assign_windows(Windows.close(id)) |> release(id)}
  end

  def handle_event("focus", %{"id" => id}, socket) do
    {:noreply, assign_windows(socket, Windows.raise_window(id))}
  end

  def handle_event("zoom", %{"id" => id}, socket) do
    {:noreply, assign_windows(socket, Windows.toggle_zoom(id))}
  end

  def handle_event("app_start", %{"name" => name}, socket) do
    {:noreply, control(socket, name, &Applications.start/1)}
  end

  def handle_event("app_stop", %{"name" => name}, socket) do
    {:noreply, control(socket, name, &Applications.stop/1)}
  end

  # Pushed by the WindowDrag hook on pointer-up, with the final coordinate.
  def handle_event("move", %{"id" => id, "x" => x, "y" => y}, socket)
      when is_integer(x) and is_integer(y) do
    {:noreply, assign_windows(socket, Windows.move(id, x, y))}
  end

  # Pushed by the WindowFrame hook when the resize grip is released.
  def handle_event("resize", %{"id" => id, "w" => w, "h" => h}, socket)
      when is_integer(w) and is_integer(h) do
    {:noreply, assign_windows(socket, Windows.resize(id, w, h))}
  end

  def handle_event("sort_processes", %{"by" => column}, socket) do
    {current, direction} = socket.assigns.process_sort

    sort =
      case Processes.sort_column(column) do
        nil -> socket.assigns.process_sort
        ^current -> {current, if(direction == :asc, do: :desc, else: :asc)}
        other -> {other, :desc}
      end

    {:noreply, socket |> assign(:process_sort, sort) |> refresh_processes(force: true)}
  end

  def handle_event("select_process", %{"id" => id}, socket) do
    {:noreply, assign(socket, selected_process: id, process_status: nil)}
  end

  def handle_event("quit_process", _params, socket) do
    {:noreply, signal_process(socket, &Processes.quit/1, "Asked")}
  end

  def handle_event("force_quit_process", _params, socket) do
    {:noreply, signal_process(socket, &Processes.force_quit/1, "Killed")}
  end

  # Escape closes the focused window, like any desktop.
  def handle_event("close_top", _params, %{assigns: %{focused: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("close_top", _params, socket) do
    id = socket.assigns.focused
    {:noreply, socket |> assign_windows(Windows.close(id)) |> release(id)}
  end

  def handle_event("i2c_rescan", _params, socket), do: {:noreply, load(socket, "i2c")}

  # ----------------------------------------------------------- Mobius window

  # A range from the menu; the window re-reads at once rather than on the
  # next poll, so the pick shows straight away.
  def handle_event("mobius_range", %{"range" => range}, socket) do
    case Metrics.fetch_range(range) do
      {:ok, range} -> {:noreply, socket |> assign(:mobius_range, range) |> reload("mobius")}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("mobius_save", _params, socket) do
    notice =
      case Metrics.save() do
        :ok -> %{ok?: true, text: "Saved" <> clock(socket)}
        {:error, reason} -> %{ok?: false, text: "Could not save: #{inspect(reason)}"}
      end

    {:noreply, assign(socket, :mobius_notice, notice)}
  end

  # Only one question at a time: picking the other replaces it.
  def handle_event("power", %{"id" => id}, socket) when is_map_key(@power_windows, id) do
    socket =
      case socket.assigns.power do
        %{id: other} when other != id -> assign_windows(socket, Windows.close(other))
        _ -> socket
      end

    dialog = @power_windows |> Map.fetch!(id) |> Map.merge(%{id: id, status: :asking})

    {:noreply,
     socket
     |> assign(:power, dialog)
     |> assign_windows(Windows.open(id))}
  end

  def handle_event("power", _params, socket), do: {:noreply, socket}

  def handle_event("power_confirm", _params, %{assigns: %{power: %{status: :asking}}} = socket) do
    dialog = socket.assigns.power

    result =
      case dialog.action do
        :restart -> Power.restart()
        :shut_down -> Power.shut_down()
      end

    status = if result == :ok, do: :pending, else: result
    {:noreply, assign(socket, :power, %{dialog | status: status})}
  end

  def handle_event("power_confirm", _params, socket), do: {:noreply, socket}

  # -------------------------------------------------------------- IEx window

  def handle_event("iex_submit", %{"line" => line}, %{assigns: %{shell: shell}} = socket)
      when is_pid(shell) do
    Shell.input(shell, line)
    # IEx does not echo what it reads; the terminal does.
    {:noreply,
     socket
     |> term_write((socket.assigns.prompt || "") <> line <> "\n")
     |> assign(:prompt, nil)}
  end

  def handle_event("iex_submit", _params, socket), do: {:noreply, socket}

  def handle_event("iex_interrupt", _params, socket) do
    if shell = socket.assigns.shell, do: Shell.interrupt(shell)
    {:noreply, socket}
  end

  def handle_event("iex_restart", _params, socket) do
    {:noreply, socket |> forget("iex") |> load("iex")}
  end

  # ----------------------------------------------------------- camera window

  def handle_event("camera_start", params, socket) do
    fields = for key <- ~w(host user password), do: params |> Map.get(key, "") |> String.trim()

    case fields do
      [host, user, password] when host != "" and user != "" and password != "" ->
        :ok = Camera.watch(host, user, password)
        {:noreply, assign(socket, camera: Camera.status(), camera_notice: nil)}

      _blank ->
        {:noreply, assign(socket, :camera_notice, "Address, user and password are all needed.")}
    end
  end

  def handle_event("camera_stop", _params, socket) do
    :ok = Camera.stop()
    {:noreply, assign(socket, camera: Camera.status(), camera_notice: nil)}
  end

  # ------------------------------------------------------------- WiFi window

  def handle_event("wifi_rescan", _params, socket) do
    {:noreply, wifi_update(socket, &%{&1 | notice: wifi_notice(WiFi.scan(), "scan")})}
  end

  def handle_event("wifi_select", %{"ssid" => ssid}, socket) do
    {:noreply,
     wifi_update(socket, fn wifi ->
       %{wifi | selected: Enum.find(wifi.networks, &(&1.ssid == ssid)), notice: nil}
     end)}
  end

  def handle_event("wifi_cancel", _params, socket) do
    {:noreply, wifi_update(socket, &%{&1 | selected: nil})}
  end

  def handle_event("wifi_join", %{"ssid" => ssid} = params, socket) do
    {:noreply,
     wifi_update(socket, fn wifi ->
       case Enum.find(wifi.networks, &(&1.ssid == ssid)) do
         %{joinable?: true} ->
           notice =
             case WiFi.join(ssid, params["psk"]) do
               :ok -> "Joining #{ssid}. VintageNet reports here as it goes."
               {:error, reason} -> "Could not configure #{ssid}: #{inspect(reason)}"
             end

           %{wifi | selected: nil, notice: notice}

         _not_joinable ->
           %{wifi | notice: "#{ssid} cannot be joined from here."}
       end
     end)}
  end

  def handle_event("wifi_forget", _params, socket) do
    {:noreply,
     wifi_update(socket, &%{&1 | selected: nil, notice: wifi_notice(WiFi.forget(), "forget")})}
  end

  # ------------------------------------------------------------ GPIO window

  def handle_event("gpio_open", %{"id" => id}, socket) do
    result =
      with {:ok, line} <- GPIO.fetch(id),
           false <- is_map_key(socket.assigns.gpio_open, id) do
        GPIO.open(line)
      else
        :error -> {:error, :unknown_line}
        true -> {:error, :already_open}
      end

    {:noreply, gpio_put(socket, id, result)}
  end

  def handle_event("gpio_close", %{"id" => id}, socket) do
    case Map.pop(socket.assigns.gpio_open, id) do
      {nil, _opens} ->
        {:noreply, socket}

      {open, opens} ->
        GPIO.close(open)
        {:noreply, assign(socket, gpio_open: opens, gpio_notice: nil)}
    end
  end

  def handle_event("gpio_direction", %{"id" => id, "direction" => direction}, socket) do
    {:noreply, gpio_change(socket, id, GPIO.direction(direction), &GPIO.set_direction/2)}
  end

  def handle_event("gpio_pull", %{"id" => id, "pull" => pull}, socket) do
    {:noreply, gpio_change(socket, id, GPIO.pull(pull), &GPIO.set_pull/2)}
  end

  def handle_event("gpio_write", %{"id" => id, "level" => level}, socket) do
    {:noreply, gpio_change(socket, id, GPIO.level(level), &GPIO.write/2)}
  end

  # ----------------------------------------------------- Files and editors

  def handle_event("fs_browse", %{"path" => path}, socket) do
    {:noreply, socket |> browse(path) |> assign(files_new: nil, files_notice: nil)}
  end

  # The Up button at the root carries no path.
  def handle_event("fs_browse", _params, socket), do: {:noreply, socket}

  def handle_event("fs_refresh", _params, socket) do
    case socket.assigns.files do
      %{path: path} -> {:noreply, browse(socket, path)}
      nil -> {:noreply, socket}
    end
  end

  def handle_event("fs_open", %{"path" => path}, socket) do
    {:noreply, open_path(socket, path)}
  end

  # Put up the naming form, but only somewhere a name could be used.
  def handle_event("fs_new", %{"kind" => kind}, socket) do
    with {:ok, kind} <- entry_kind(kind),
         true <- files_writable?(socket.assigns.files) do
      {:noreply, assign(socket, files_new: kind, files_notice: nil)}
    else
      _read_only -> {:noreply, socket}
    end
  end

  def handle_event("fs_cancel", _params, socket) do
    {:noreply, assign(socket, files_new: nil, files_notice: nil)}
  end

  # A new file opens in the editor straight away; a new folder just appears.
  def handle_event("fs_create", %{"kind" => kind, "name" => name}, socket) do
    with %{path: dir} <- socket.assigns.files,
         {:ok, kind} <- entry_kind(kind) do
      name = String.trim(name)

      case Files.create(dir, name, kind) do
        {:ok, path} ->
          socket = socket |> browse(dir) |> assign(files_new: nil, files_notice: nil)
          {:noreply, if(kind == :file, do: open_path(socket, path), else: socket)}

        {:error, reason} ->
          notice = "Could not create #{name}: #{reason_text(reason)}"
          {:noreply, assign(socket, :files_notice, notice)}
      end
    else
      _no_window -> {:noreply, socket}
    end
  end

  # The editor's form names its window; "id" would shadow the form's own.
  def handle_event("edit_change", %{"window" => id, "text" => text}, socket) do
    {:noreply, update_editor(socket, id, &%{&1 | text: normalize(text)})}
  end

  def handle_event("edit_save", %{"window" => id, "text" => text}, socket) do
    {:noreply, save(socket, id, normalize(text))}
  end

  # On a kiosk the browser runs Myelin scripts (the screensaver, for one) that
  # report what they do by pushing "myelin:<script>:<event>" to the LiveView.
  # Nothing reacts to them yet; the clause keeps an unhandled event from
  # crashing the desktop on the device's own screen.
  def handle_event("myelin:" <> _event, _params, socket), do: {:noreply, socket}

  # Derived once per update so the template never has to reach for it: the
  # window with the highest z is the focused one, exactly as on a real desktop.
  defp assign_windows(socket, windows) do
    open = for {id, w} <- windows, w.open?, do: {id, w}

    open_ids = Enum.map(open, &elem(&1, 0))

    # Windows that exist per application or per file are named by their id.
    dynamic = open_ids |> Enum.sort() |> Enum.flat_map(&List.wrap(dynamic_window(&1)))

    # The Deskbar tray lists what is *running*, the way Haiku's does. Launching
    # is the desktop icons' job, so a closed window has no business here.
    tray = Enum.filter(@apps, &(&1.id in open_ids)) ++ dynamic

    socket
    |> assign(:windows, windows)
    |> assign(:open, open_ids)
    |> assign(:tray, tray)
    |> assign(
      :focused,
      open |> Enum.max_by(fn {_id, w} -> w.z end, fn -> {nil, nil} end) |> elem(0)
    )
  end

  defp dynamic_window("app-" <> name = id), do: %{id: id, title: name, icon: @app_icon}
  defp dynamic_window("edit-" <> _ = id), do: file_window(id, @editor_icon)
  defp dynamic_window("alert-" <> _ = id), do: file_window(id, @alert_icon)

  defp dynamic_window("power-" <> _ = id) do
    case @power_windows do
      %{^id => %{title: title}} -> %{id: id, title: title, icon: @power_icon}
      _ -> nil
    end
  end

  defp dynamic_window(_id), do: nil

  defp file_window(id, icon) do
    case file_window_path(id) do
      {:ok, path} -> %{id: id, title: Path.basename(path), icon: icon}
      :error -> nil
    end
  end

  # ------------------------------------------------------- polled windows

  defp polled?("applications"), do: true
  defp polled?("gpio"), do: true
  defp polled?("mobius"), do: true
  defp polled?("app-" <> _name), do: true
  defp polled?(_id), do: false

  # Load a window's contents now and, if it is a polled one, keep them fresh
  # once connected until it closes. A window with nothing to load is left be.
  # Open state is persisted, so a window whose contents cannot be read would
  # otherwise crash every mount from then on, and on a kiosk that is the
  # whole screen. It is closed instead, and the reason logged.
  defp restore(socket, id) do
    track(socket, id)
  rescue
    error ->
      Logger.error(
        "closing the #{id} window, it could not be restored: " <>
          Exception.format(:error, error, __STACKTRACE__)
      )

      socket |> assign_windows(Windows.close(id)) |> release(id)
  end

  defp track(socket, id) do
    cond do
      id not in socket.assigns.open -> socket
      polled?(id) -> socket |> load(id) |> ensure_polling(id)
      true -> load(socket, id)
    end
  end

  defp ensure_polling(socket, id) do
    if connected?(socket) and not MapSet.member?(socket.assigns.polling, id) do
      schedule_poll(id)
      update(socket, :polling, &MapSet.put(&1, id))
    else
      socket
    end
  end

  defp schedule_poll(id), do: Process.send_after(self(), {:poll, id}, @poll_interval)

  defp load(socket, "applications"), do: assign(socket, :applications, Applications.list())

  # The list shows who holds what, so it is worth re-reading; the levels of
  # held inputs mostly arrive as notifications, and this catches the rest.
  defp load(socket, "gpio") do
    socket
    |> assign(:gpio, %{lines: GPIO.list(), simulated?: GPIO.simulated?()})
    |> update(:gpio_open, &Map.new(&1, fn {id, open} -> {id, GPIO.refresh(open)} end))
  end

  defp load(socket, "app-" <> name = id) do
    info =
      case Applications.fetch_name(name) do
        {:ok, app} -> Applications.info(app)
        :error -> nil
      end

    update(socket, :app_info, &Map.put(&1, id, info))
  end

  # The listing is re-read whenever the window is opened or raised, which
  # doubles as a refresh; the directory it shows is kept until it closes.
  defp load(%{assigns: %{files: %{path: path}}} = socket, "files"), do: browse(socket, path)
  defp load(socket, "files"), do: browse(socket, "/")

  # A file is read once, when its window opens: reading it again on every
  # raise would throw away what has been typed since. Restoring the window
  # after a reload reads the file; if it is gone by then, so is the window.
  defp load(socket, "edit-" <> _ = id) do
    with false <- Map.has_key?(socket.assigns.editors, id),
         {:ok, path} <- file_window_path(id),
         {:ok, text} <- Files.read(path) do
      put_editor(socket, id, editor(path, text))
    else
      true -> socket
      _unreadable -> assign_windows(socket, Windows.close(id))
    end
  end

  # An alert is answered, not restored: after a reload it is simply gone.
  defp load(socket, "alert-" <> _ = id) do
    if Map.has_key?(socket.assigns.alerts, id),
      do: socket,
      else: assign_windows(socket, Windows.close(id))
  end

  # So is Restart or Shut Down: after a reload, or the restart itself, the
  # question is gone.
  defp load(socket, "power-" <> _ = id) do
    case socket.assigns.power do
      %{id: ^id} -> socket
      _ -> assign_windows(socket, Windows.close(id))
    end
  end

  # Every poll re-reads the range on show; the notice about the last Save
  # Now stays until the window closes.
  defp load(socket, "mobius"),
    do: assign(socket, :mobius, Metrics.history(socket.assigns.mobius_range))

  # Read when the window opens and on Rescan, never on a timer: a scan
  # touches every address on the bus.
  defp load(socket, "i2c"),
    do: assign(socket, i2c: I2C.scan(), i2c_scanned_at: socket.assigns.now)

  # The camera process reports every change; the window only has to listen.
  defp load(socket, "camera") do
    if connected?(socket), do: Camera.subscribe()
    assign(socket, camera: Camera.status(), camera_notice: nil)
  end

  # Read once when the window opens; from then on VintageNet says when
  # something changes. The subscription only makes sense on the live socket.
  defp load(socket, "wifi") do
    if WiFi.available?() do
      if connected?(socket), do: WiFi.subscribe()

      assign(socket, :wifi, %{
        available?: true,
        ifname: WiFi.ifname(),
        status: WiFi.status(),
        networks: WiFi.networks(),
        selected: nil,
        notice: wifi_notice(WiFi.scan(), "scan"),
        scanned?: false
      })
    else
      assign(socket, :wifi, %{available?: false, ifname: WiFi.ifname()})
    end
  end

  # One IEx session per window, started once the socket is live; the dead
  # render would only start one to throw it away.
  defp load(socket, "iex") do
    if connected?(socket) and is_nil(socket.assigns.shell) do
      {:ok, shell} = Shell.start(self())
      assign(socket, shell: shell, shell_ref: Process.monitor(shell), prompt: nil)
    else
      socket
    end
  end

  defp load(socket, _id), do: socket

  defp reload(socket, id), do: if(id in socket.assigns.open, do: load(socket, id), else: socket)

  # A polled window's data is dropped by its poll loop once that notices the
  # close, so the loop ends cleanly; anything else is dropped right away.
  defp release(socket, id), do: if(polled?(id), do: socket, else: forget(socket, id))

  defp forget(socket, "applications"), do: assign(socket, :applications, nil)

  # Closing the window gives every line back.
  defp forget(socket, "gpio") do
    Enum.each(socket.assigns.gpio_open, fn {_id, open} -> GPIO.close(open) end)
    assign(socket, gpio: nil, gpio_open: %{}, gpio_notice: nil)
  end

  defp forget(socket, "app-" <> _name = id) do
    socket
    |> update(:app_info, &Map.delete(&1, id))
    |> update(:app_errors, &Map.delete(&1, id))
  end

  defp forget(socket, "files"), do: assign(socket, files: nil, files_new: nil, files_notice: nil)
  defp forget(socket, "edit-" <> _ = id), do: update(socket, :editors, &Map.delete(&1, id))
  defp forget(socket, "alert-" <> _ = id), do: update(socket, :alerts, &Map.delete(&1, id))

  defp forget(socket, "power-" <> _ = id) do
    case socket.assigns.power do
      %{id: ^id} -> assign(socket, :power, nil)
      _ -> socket
    end
  end

  # The camera keeps going for the other viewers; this window just stops listening.
  defp forget(socket, "camera") do
    Camera.unsubscribe()
    assign(socket, camera: nil, camera_notice: nil)
  end

  defp forget(socket, "wifi") do
    if match?(%{available?: true}, socket.assigns.wifi), do: WiFi.unsubscribe()
    assign(socket, :wifi, nil)
  end

  # The range is kept, so reopening shows the same span as before.
  defp forget(socket, "mobius"), do: assign(socket, mobius: nil, mobius_notice: nil)

  # Closing the window ends the session, and the scrollback with it.
  defp forget(socket, "iex") do
    if socket.assigns.shell_ref, do: Process.demonitor(socket.assigns.shell_ref, [:flush])
    if socket.assigns.shell, do: Shell.stop(socket.assigns.shell)

    socket
    |> assign(shell: nil, shell_ref: nil, prompt: nil, term_style: ANSI.initial())
    |> stream(:out, [], reset: true)
  end

  defp forget(socket, _id), do: socket

  # Start or stop an application from its window and show the outcome at
  # once rather than on the next poll.
  defp control(socket, name, fun) do
    id = window_id(name)

    result =
      case Applications.fetch_name(name) do
        {:ok, app} -> fun.(app)
        :error -> {:error, :not_loaded}
      end

    socket
    |> update(:app_errors, &put_notice(&1, id, result))
    |> reload(id)
    |> reload("applications")
  end

  defp put_notice(errors, id, :ok), do: Map.delete(errors, id)

  defp put_notice(errors, id, {:error, :protected}),
    do: Map.put(errors, id, "needed by this desktop")

  defp put_notice(errors, id, {:error, :not_loaded}), do: Map.put(errors, id, "not loaded")
  defp put_notice(errors, id, {:error, reason}), do: Map.put(errors, id, inspect(reason))

  # Apply a setting from the wire to one held line. An unparsable setting or
  # a line this view does not hold is ignored; a refused change is explained.
  defp gpio_change(socket, id, {:ok, setting}, fun) do
    case socket.assigns.gpio_open do
      %{^id => open} -> gpio_put(socket, id, fun.(open, setting))
      _not_held -> socket
    end
  end

  defp gpio_change(socket, _id, :error, _fun), do: socket

  defp gpio_put(socket, id, {:ok, open}) do
    socket
    |> update(:gpio_open, &Map.put(&1, id, open))
    |> assign(:gpio_notice, nil)
  end

  defp gpio_put(socket, id, {:error, reason}) do
    assign(socket, :gpio_notice, gpio_notice(id, reason))
  end

  defp gpio_notice(id, :ebusy), do: "#{id} is in use elsewhere"
  defp gpio_notice(id, :unknown_line), do: "#{id} is not a line on this device"
  defp gpio_notice(id, :already_open), do: "#{id} is already open"
  defp gpio_notice(id, reason), do: "#{id}: #{inspect(reason)}"

  # ----------------------------------------------------- files and editors

  defp browse(socket, path), do: assign(socket, :files, Files.list(path))

  # Open a file in its editor window, or raise the one it already has. A
  # file that is not text gets an alert instead, one per file, so opening
  # the same firmware image twice does not stack two of them.
  defp open_path(socket, path) do
    id = file_window_id(:edit, path)

    if Map.has_key?(socket.assigns.editors, id) do
      assign_windows(socket, Windows.open(id))
    else
      case Files.read(path) do
        {:ok, text} ->
          socket |> assign_windows(Windows.open(id)) |> put_editor(id, editor(path, text))

        {:error, reason} ->
          alert_id = file_window_id(:alert, path)
          alert = %{path: path, name: Path.basename(path), reason: reason}

          socket
          |> assign_windows(Windows.open(alert_id))
          |> update(:alerts, &Map.put(&1, alert_id, alert))
      end
    end
  end

  defp editor(path, text) do
    text = normalize(text)

    %{
      path: path,
      name: Path.basename(path),
      text: text,
      saved: text,
      writable?: Files.writable?(path),
      status: nil
    }
  end

  defp put_editor(socket, id, editor), do: update(socket, :editors, &Map.put(&1, id, editor))

  defp update_editor(socket, id, fun) do
    case socket.assigns.editors do
      %{^id => editor} -> put_editor(socket, id, fun.(editor))
      _not_open -> socket
    end
  end

  # Write the text out and say so. The listing is re-read if it shows the
  # file's directory, so the new size appears without a click.
  defp save(socket, id, text) do
    case socket.assigns.editors do
      %{^id => editor} ->
        case Files.write(editor.path, text) do
          :ok ->
            saved = %{editor | text: text, saved: text, status: "Saved" <> clock(socket)}
            socket |> put_editor(id, saved) |> refresh_files(Path.dirname(editor.path))

          {:error, reason} ->
            status = "Could not save: #{reason_text(reason)}"
            put_editor(socket, id, %{editor | text: text, status: status})
        end

      _not_open ->
        socket
    end
  end

  defp refresh_files(socket, dir) do
    case socket.assigns.files do
      %{path: ^dir} -> browse(socket, dir)
      _elsewhere -> socket
    end
  end

  # A textarea submits Windows line endings whatever the file had, so text is
  # kept with the newlines the device expects.
  defp normalize(text), do: String.replace(text, "\r\n", "\n")

  defp clock(%{assigns: %{now: nil}}), do: ""
  defp clock(%{assigns: %{now: now}}), do: " at " <> Calendar.strftime(now, "%H:%M:%S")

  defp files_writable?(%{writable?: writable?, error: nil}), do: writable?
  defp files_writable?(_none_or_unreadable), do: false

  # Kinds from the wire, without creating atoms.
  defp entry_kind("file"), do: {:ok, :file}
  defp entry_kind("directory"), do: {:ok, :directory}
  defp entry_kind(_other), do: :error

  # Change the WiFi window's state, if it is open and there is WiFi to show.
  defp wifi_update(%{assigns: %{wifi: %{available?: true} = wifi}} = socket, fun),
    do: assign(socket, :wifi, fun.(wifi))

  defp wifi_update(socket, _fun), do: socket

  defp wifi_notice(:ok, _what), do: nil
  defp wifi_notice({:error, reason}, what), do: "The #{what} failed: #{inspect(reason)}"

  # Chunks the IEx window has printed are streamed, so the server keeps none of
  # them; only the ANSI state at the end of the last chunk carries over.
  @scrollback 400

  defp term_write(socket, text) do
    {html, style} = ANSI.to_html(text, socket.assigns.term_style)
    seq = socket.assigns.term_seq + 1

    socket
    |> assign(term_style: style, term_seq: seq)
    |> stream_insert(:out, %{id: seq, html: html}, limit: -@scrollback)
  end

  # Listing a few hundred processes every second is wasted work while nobody is
  # looking at them, so this only runs when the window is open.
  defp refresh_processes(socket, opts \\ []) do
    if "processes" in socket.assigns.open or opts[:force] do
      {column, direction} = socket.assigns.process_sort
      assign(socket, :processes, Processes.list(column, direction))
    else
      socket
    end
  end

  # Core usage is measured since this process last asked cpu_sup, so it is
  # only asked while the Resources window is open: opening makes a throwaway
  # call to start the window and the next tick has the first reading. A tick
  # landing inside the same clock tick as the previous call would read 100%,
  # so those are skipped. Closing forgets the window, so reopening never shows
  # an average over however long it was shut.
  defp refresh_cpu(socket) do
    now = System.monotonic_time(:millisecond)

    cond do
      not socket.assigns.cpu_supported? ->
        socket

      "resources" not in socket.assigns.open ->
        assign(socket, cpu_read_at: nil, cpu: @no_cpu)

      socket.assigns.cpu_read_at == nil ->
        DeviceInfo.cpu()
        assign(socket, :cpu_read_at, now)

      now - socket.assigns.cpu_read_at < @cpu_min_window ->
        socket

      true ->
        assign(socket, cpu_read_at: now, cpu: DeviceInfo.cpu() || socket.assigns.cpu)
    end
  end

  defp signal_process(%{assigns: %{selected_process: nil}} = socket, _fun, _verb), do: socket

  defp signal_process(socket, fun, verb) do
    id = socket.assigns.selected_process

    status =
      case fun.(id) do
        :ok -> "#{verb} #{id}"
        {:error, :not_alive} -> "#{id} was already gone"
        {:error, :unknown_pid} -> "#{id} is not a pid"
      end

    socket
    |> assign(:process_status, status)
    |> refresh_processes(force: true)
  end

  # Open a window and, once the browser has said how big the desktop is,
  # make sure it sits inside.
  defp open_fitted(id, nil), do: Windows.open(id)

  defp open_fitted(id, viewport) do
    _opened = Windows.open(id)
    Windows.fit([{id, window_width(id)}], viewport)
  end

  # The width a window is rendered at until someone resizes it, as the
  # templates below set it.
  defp window_width("app-" <> _name), do: 520
  defp window_width("edit-" <> _path), do: 560
  defp window_width("alert-" <> _path), do: 400
  defp window_width("power-" <> _action), do: 400

  defp window_width(id) do
    case Enum.find(@apps, &(&1.id == id)) do
      %{width: width} -> width
      nil -> 460
    end
  end

  # Windows we have no state for yet are simply not open.
  defp placement(windows, id), do: Map.get(windows, id, %{x: 0, y: 0, z: 1, zoomed?: false})

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="desktop"
      class="be-desktop"
      phx-hook="Desktop"
      phx-window-keydown="close_top"
      phx-key="Escape"
    >
      <aside class="be-desktop__icons" aria-label="Desktop">
        <.desktop_icon
          :for={app <- @apps}
          id={app.id}
          icon={app.icon}
          label={app.label}
          open={app.id in @open}
        />
      </aside>

      <.window
        :if={"system" in @open}
        id="system"
        title="About This System"
        icon="computer"
        width={460}
        active={@focused == "system"}
        window={placement(@windows, "system")}
      >
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
        <.cpu_meter :if={@cpu_supported?} cpu={@cpu} />

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

      <.window
        :if={"processes" in @open}
        id="processes"
        title="Processes"
        icon="system-run"
        width={640}
        active={@focused == "processes"}
        window={placement(@windows, "processes")}
      >
        <:menu>
          <.menu_item phx-click="quit_process">Quit</.menu_item>
          <.menu_item phx-click="force_quit_process">Force Quit</.menu_item>
        </:menu>

        <div class="flex h-full min-h-0 flex-col">
          <div class="be-doc be-table-wrap">
            <table class="be-table">
              <thead>
                <tr>
                  <.column_header
                    event="sort_processes"
                    sort={@process_sort}
                    column={:name}
                    label="Process"
                  />
                  <.column_header
                    event="sort_processes"
                    sort={@process_sort}
                    column={:pid}
                    label="PID"
                  />
                  <.column_header
                    event="sort_processes"
                    sort={@process_sort}
                    column={:memory}
                    label="Memory"
                    numeric
                  />
                  <.column_header
                    event="sort_processes"
                    sort={@process_sort}
                    column={:reductions}
                    label="Reductions"
                    numeric
                  />
                  <.column_header
                    event="sort_processes"
                    sort={@process_sort}
                    column={:message_queue_len}
                    label="Msg Q"
                    numeric
                  />
                  <.column_header
                    event="sort_processes"
                    sort={@process_sort}
                    column={:status}
                    label="Status"
                  />
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={process <- @processes}
                  phx-click="select_process"
                  phx-value-id={process.id}
                  aria-selected={to_string(@selected_process == process.id)}
                >
                  <td class="be-table__name" title={process.current}>{process.name}</td>
                  <td class="be-mono">{process.id}</td>
                  <td class="be-table__num">{format_bytes(process.memory)}</td>
                  <td class="be-table__num">{format_count(process.reductions)}</td>
                  <td class="be-table__num">{process.message_queue_len}</td>
                  <td>{process.status}</td>
                </tr>
              </tbody>
            </table>
          </div>

          <div class="mt-3 flex shrink-0 flex-wrap items-center gap-3">
            <button
              type="button"
              class="be-btn"
              phx-click="quit_process"
              disabled={is_nil(@selected_process)}
            >
              <.haiku_icon name="application-exit" size={16} /> Quit
            </button>
            <button
              type="button"
              class="be-btn"
              phx-click="force_quit_process"
              disabled={is_nil(@selected_process)}
            >
              <.haiku_icon name="process-stop" size={16} /> Force Quit
            </button>
            <span class="text-[11px] text-be-ink-soft">
              {@process_status || process_hint(@selected_process, @processes)}
            </span>
          </div>
        </div>
      </.window>

      <.window
        :if={"applications" in @open}
        id="applications"
        title="Applications"
        icon="applications-engineering"
        width={560}
        active={@focused == "applications"}
        window={placement(@windows, "applications")}
      >
        <.app_list applications={@applications || []} open={@open} icon={@app_icon} />
      </.window>

      <.window
        :if={"gpio" in @open}
        id="gpio"
        title="GPIO"
        icon="input-gaming"
        width={560}
        active={@focused == "gpio"}
        window={placement(@windows, "gpio")}
      >
        <.gpio_panel gpio={@gpio} open={@gpio_open} notice={@gpio_notice} />
      </.window>

      <.window
        :if={"files" in @open}
        id="files"
        title="Files"
        icon="system-file-manager"
        width={620}
        active={@focused == "files"}
        window={placement(@windows, "files")}
      >
        <:menu>
          <.menu_item
            phx-click="fs_new"
            phx-value-kind="file"
            disabled={not files_writable?(@files)}
            title={if files_writable?(@files), do: nil, else: "This folder is read-only"}
          >
            New File
          </.menu_item>
          <.menu_item
            phx-click="fs_new"
            phx-value-kind="directory"
            disabled={not files_writable?(@files)}
            title={if files_writable?(@files), do: nil, else: "This folder is read-only"}
          >
            New Folder
          </.menu_item>
          <.menu_item phx-click="fs_refresh">Refresh</.menu_item>
        </:menu>

        <.file_browser files={@files} new={@files_new} notice={@files_notice} />
      </.window>

      <.window
        :for={{id, editor} <- @editors}
        id={id}
        title={editor.name}
        icon={@editor_icon}
        width={560}
        active={@focused == id}
        window={placement(@windows, id)}
      >
        <:menu>
          <.menu_item type="submit" form={editor_form_id(id)} disabled={not editor.writable?}>
            Save
          </.menu_item>
        </:menu>

        <.text_editor id={id} editor={editor} />
      </.window>

      <.window
        :for={{id, alert} <- @alerts}
        id={id}
        title={alert.name}
        icon={@alert_icon}
        width={400}
        active={@focused == id}
        window={placement(@windows, id)}
      >
        <.no_viewer id={id} alert={alert} />
      </.window>

      <.window
        :if={@power}
        id={@power.id}
        title={@power.title}
        icon={@power_icon}
        width={400}
        active={@focused == @power.id}
        window={placement(@windows, @power.id)}
      >
        <.power_dialog power={@power} />
      </.window>

      <.window
        :if={"i2c" in @open}
        id="i2c"
        title="I2C"
        icon="plugins"
        width={520}
        active={@focused == "i2c"}
        window={placement(@windows, "i2c")}
      >
        <:menu>
          <.menu_item phx-click="i2c_rescan">Rescan</.menu_item>
        </:menu>
        <.i2c_panel scan={@i2c} scanned_at={@i2c_scanned_at} />
      </.window>

      <.window
        :if={"camera" in @open}
        id="camera"
        title="Security Camera"
        icon="camera-video"
        width={640}
        active={@focused == "camera"}
        window={placement(@windows, "camera")}
      >
        <:menu>
          <.menu_item phx-click="camera_stop">Stop</.menu_item>
        </:menu>
        <.camera_panel camera={@camera} notice={@camera_notice} />
      </.window>

      <.window
        :if={"wifi" in @open}
        id="wifi"
        title="WiFi"
        icon="preferences-system-network"
        width={520}
        active={@focused == "wifi"}
        window={placement(@windows, "wifi")}
      >
        <:menu>
          <.menu_item phx-click="wifi_rescan">Rescan</.menu_item>
          <.menu_item phx-click="wifi_forget" data-confirm="Forget every saved network?">
            Forget
          </.menu_item>
        </:menu>
        <.wifi_panel wifi={@wifi} />
      </.window>

      <.window
        :if={"mobius" in @open}
        id="mobius"
        title="Mobius"
        icon="office-chart-line"
        width={600}
        active={@focused == "mobius"}
        window={placement(@windows, "mobius")}
      >
        <:menu>
          <.menu_item
            :for={{range, label} <- Metrics.ranges()}
            phx-click="mobius_range"
            phx-value-range={range}
            aria-pressed={to_string(range == @mobius_range)}
          >
            {label}
          </.menu_item>
          <.menu_item phx-click="mobius_save">Save Now</.menu_item>
        </:menu>
        <.mobius_panel history={@mobius} notice={@mobius_notice} dir={@mobius_dir} />
      </.window>

      <.window
        :if={"iex" in @open}
        id="iex"
        title="IEx"
        icon="terminal"
        width={640}
        active={@focused == "iex"}
        window={placement(@windows, "iex")}
      >
        <:menu>
          <.menu_item phx-click="iex_interrupt">Interrupt</.menu_item>
          <.menu_item phx-click="iex_restart">Restart</.menu_item>
        </:menu>
        <.terminal out={@streams.out} prompt={@prompt} shell={@shell} />
      </.window>

      <.window
        :for={"app-" <> name = id <- @open}
        id={id}
        title={name}
        icon={@app_icon}
        width={520}
        active={@focused == id}
        window={placement(@windows, id)}
      >
        <.app_details
          name={name}
          info={@app_info[id]}
          error={@app_errors[id]}
          required={@required}
          icon={@app_icon}
        />
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

  # The machine as a whole on a meter like the others, then one thin meter
  # per core. Usage is a rate, so the first second after opening is blank.
  attr :cpu, :map, required: true, doc: "from HelloLiveView.DeviceInfo.cpu/0"

  defp cpu_meter(assigns) do
    ~H"""
    <div class="mb-4 last:mb-0">
      <div class="mb-1 flex items-baseline gap-2">
        <.haiku_icon name="computer" size={16} />
        <span class="text-[12px] font-semibold">CPU usage</span>
        <span class="ml-auto text-[12px] font-semibold tabular-nums">
          {if @cpu.total, do: "#{@cpu.total}% · #{length(@cpu.cores)} cores", else: "measuring…"}
        </span>
      </div>
      <div class="be-meter">
        <div
          class={["be-meter__fill", (@cpu.total || 0) >= 85 && "be-meter__fill--warn"]}
          style={"width: #{@cpu.total || 0}%"}
        >
        </div>
      </div>
      <div :if={@cpu.cores != []} class="be-cores mt-2">
        <div :for={core <- @cpu.cores} class="be-core">
          <span class="be-mono">{core.name}</span>
          <div class="be-meter">
            <div
              class={["be-meter__fill", core.percent >= 85 && "be-meter__fill--warn"]}
              style={"width: #{core.percent}%"}
            >
            </div>
          </div>
          <span class="be-core__value">{core.percent}%</span>
        </div>
      </div>
    </div>
    """
  end

  # The Be alert for Restart and Shut Down: a question, then Cancel or go.
  # Once answered, the buttons give way to what happened.
  attr :power, :map, required: true

  defp power_dialog(assigns) do
    ~H"""
    <div class="flex items-start gap-4">
      <.haiku_icon name="dialog-warning" size={40} />
      <div class="min-w-0 flex-1">
        <p class="text-[13px] font-bold">{power_question(@power)}</p>
        <p class="mt-1 text-be-ink-soft">{power_detail(@power)}</p>
      </div>
    </div>
    <div class="mt-4 flex justify-end gap-2">
      <%= if @power.status == :asking do %>
        <button type="button" class="be-btn" phx-click="close" phx-value-id={@power.id}>
          Cancel
        </button>
        <button type="button" class="be-btn be-btn--default" phx-click="power_confirm">
          {@power.title}
        </button>
      <% else %>
        <button
          type="button"
          class="be-btn be-btn--default"
          phx-click="close"
          phx-value-id={@power.id}
          disabled={@power.status == :pending}
        >
          OK
        </button>
      <% end %>
    </div>
    """
  end

  defp power_question(%{action: :restart}), do: "Do you really want to restart the system?"
  defp power_question(%{action: :shut_down}), do: "Do you really want to shut down the system?"

  defp power_detail(%{status: :asking, action: :restart}),
    do: "Open windows are remembered and come back afterwards."

  defp power_detail(%{status: :asking, action: :shut_down}),
    do: "The device stays off until its power is cycled."

  defp power_detail(%{status: :pending, action: :restart}),
    do: "Restarting… the desktop returns once the device is back up."

  defp power_detail(%{status: :pending, action: :shut_down}),
    do: "Shutting down… the device is off once the screen goes dark."

  defp power_detail(%{status: {:error, :host}, action: action}),
    do: "There is no device to #{power_verb(action)}: this desktop is running on the host."

  defp power_detail(%{status: {:error, reason}, action: action}),
    do: "Could not #{power_verb(action)}: #{inspect(reason)}"

  defp power_verb(:restart), do: "restart"
  defp power_verb(:shut_down), do: "shut down"

  defp process_hint(nil, processes),
    do: "#{length(processes)} processes — select one to act on it"

  defp process_hint(id, _processes), do: "Selected #{id}"

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
end
