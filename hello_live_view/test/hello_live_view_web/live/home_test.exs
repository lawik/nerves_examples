defmodule HelloLiveViewWeb.HomeTest do
  use HelloLiveViewWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import HelloLiveViewWeb.Components.Files, only: [file_window_id: 2]

  alias HelloLiveView.Windows

  setup do
    Windows.reset()
    on_exit(fn -> Windows.reset() end)
    :ok
  end

  defp open_navigator(view) do
    view
    |> element("button.be-icon-tile[phx-value-id=applications]")
    |> render_click()
  end

  defp assigns(view), do: :sys.get_state(view.pid).socket.assigns

  # /tmp is a writable root on the host as well as on a device, so a folder
  # of its own under there is where a test may create things.
  defp files_dir do
    dir = Path.join("/tmp/hello_live_view_test", "desktop-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  test "events from the kiosk browser's scripts are accepted", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert render_hook(view, "myelin:screensaver:show", %{})
    assert render_hook(view, "myelin:screensaver:hide", %{})
    assert Process.alive?(view.pid)
  end

  test "the GPIO window opens lines, drives them and gives them back", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    html = view |> element("button.be-icon-tile[phx-value-id=gpio]") |> render_click()
    assert html =~ "lines free"
    assert html =~ "simulated"

    # The stub's first pair: what one drives, the other reads.
    [a, b | _] = HelloLiveView.GPIO.list()

    render_click(view, "gpio_open", %{"id" => a.id})
    render_click(view, "gpio_open", %{"id" => b.id})
    assert has_element?(view, "#gpio-#{a.id} .be-tag--idle", "low")

    assert has_element?(
             view,
             "#gpio-#{a.id} button[phx-value-direction=input][aria-pressed=true]"
           )

    assert has_element?(view, "#gpio button.be-list__row[phx-value-id=#{a.id}][disabled]", "open")

    render_click(view, "gpio_direction", %{"id" => a.id, "direction" => "output"})
    render_click(view, "gpio_write", %{"id" => a.id, "level" => "1"})
    assert has_element?(view, "#gpio-#{a.id} .be-tag--ok", "high")

    # Its partner is an input this view holds, so the change arrived as a
    # notification rather than waiting for the next poll.
    assert has_element?(view, "#gpio-#{b.id} .be-tag--ok", "high")

    render_click(view, "gpio_close", %{"id" => a.id})
    refute has_element?(view, "#gpio-#{a.id}")
    assert has_element?(view, "#gpio-#{b.id}")

    # Closing the window gives back what is left, once the poll notices.
    render_click(view, "close", %{"id" => "gpio"})
    send(view.pid, {:poll, "gpio"})
    assert assigns(view).gpio_open == %{}
    assert assigns(view).gpio == nil
  end

  test "the GPIO window explains a line it cannot open", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    render_click(view, "open", %{"id" => "gpio"})

    render_click(view, "gpio_open", %{"id" => "gpiochip9-99"})
    assert has_element?(view, "#gpio .be-tag--warn", "not a line on this device")

    # Settings for a line this view does not hold are ignored, not crashed on.
    render_click(view, "gpio_write", %{"id" => "gpiochip0-5", "level" => "1"})
    render_click(view, "gpio_direction", %{"id" => "gpiochip0-5", "direction" => "sideways"})
    assert Process.alive?(view.pid)

    render_click(view, "close", %{"id" => "gpio"})
    send(view.pid, {:poll, "gpio"})
  end

  test "the I2C window scans the buses when it opens and again on request", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    html = view |> element("button.be-icon-tile[phx-value-id=i2c]") |> render_click()
    assert html =~ "i2c-test-0"
    assert html =~ "0x10"
    assert html =~ "simulated"

    html = view |> element("#i2c .be-window__menu button", "Rescan") |> render_click()
    assert html =~ "0x20"
    assert html =~ "scanned"

    render_click(view, "close", %{"id" => "i2c"})
    refute has_element?(view, "#i2c")
  end

  test "the title and the Deskbar carry the hostname", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    hostname = HelloLiveView.DeviceInfo.hostname()

    assert page_title(view) =~ hostname
    assert has_element?(view, ".be-deskbar__title", hostname)
  end

  # The IEx session answers on its own time.
  defp eventually(fun, attempts \\ 60) do
    cond do
      fun.() -> true
      attempts == 0 -> false
      true -> Process.sleep(50) && eventually(fun, attempts - 1)
    end
  end

  test "the IEx window runs a real IEx session with Toolshed", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("button.be-icon-tile[phx-value-id=iex]") |> render_click()

    assert eventually(fn -> render(view) =~ "Interactive Elixir" end)
    assert eventually(fn -> render(view) =~ "iex(1)&gt;" end)

    view |> form("#iex form", line: "21 * 2") |> render_submit()
    assert eventually(fn -> render(view) =~ "42" end)
    # What was typed is echoed, as a terminal would.
    assert render(view) =~ "iex(1)&gt; 21 * 2"

    view |> form("#iex form", line: ~s|cmd("echo toolshed-ok")|) |> render_submit()
    assert eventually(fn -> render(view) =~ "toolshed-ok" end)

    shell = assigns(view).shell
    assert Process.alive?(shell)
    render_click(view, "close", %{"id" => "iex"})
    refute Process.alive?(shell)
    assert assigns(view).shell == nil
  end

  test "the leaf menu opens About This System", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view |> element("#deskbar-menu button", "About This System") |> render_click()
    assert has_element?(view, "#system")
  end

  test "the leaf menu asks before restarting or shutting down", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    html = view |> element("#deskbar-menu button", "Restart…") |> render_click()
    assert html =~ "Do you really want to restart the system?"
    assert has_element?(view, "#power-restart")

    # Picking the other question replaces the first.
    html = view |> element("#deskbar-menu button", "Shut Down…") |> render_click()
    assert html =~ "Do you really want to shut down the system?"
    refute has_element?(view, "#power-restart")

    # On the host there is no device; saying so is all that happens.
    html = view |> element("#power-shut-down button", "Shut Down") |> render_click()
    assert html =~ "running on the host"
    assert Process.alive?(view.pid)

    view |> element("#power-shut-down button", "OK") |> render_click()
    refute has_element?(view, "#power-shut-down")
    assert assigns(view).power == nil
  end

  test "Cancel and Escape both drop the question", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view |> element("#deskbar-menu button", "Restart…") |> render_click()
    view |> element("#power-restart button", "Cancel") |> render_click()
    refute has_element?(view, "#power-restart")

    view |> element("#deskbar-menu button", "Restart…") |> render_click()
    render_keydown(view, "close_top", %{"key" => "Escape"})
    refute has_element?(view, "#power-restart")
    assert assigns(view).power == nil
  end

  test "the WiFi window says so when there is no WiFi to configure", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    html = view |> element("button.be-icon-tile[phx-value-id=wifi]") |> render_click()
    assert html =~ "no WiFi to configure here"
    assert html =~ "wlan0"

    # Events for a window with nothing behind it are shrugged off.
    render_click(view, "wifi_rescan", %{})
    render_click(view, "wifi_select", %{"ssid" => "home"})
    assert Process.alive?(view.pid)

    render_click(view, "close", %{"id" => "wifi"})
    assert assigns(view).wifi == nil
  end

  test "the Applications window lists loaded applications", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    html = open_navigator(view)

    assert html =~ "loaded applications started"
    assert has_element?(view, "#applications button[phx-value-id=app-kernel]", "kernel")
  end

  test "selecting an application opens its window", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    open_navigator(view)

    view |> element("#applications button[phx-value-id=app-kernel]") |> render_click()

    assert has_element?(view, "#app-kernel .be-stat", "Processes")
    assert has_element?(view, "#app-kernel .be-tag", "started")
    assert has_element?(view, "#app-kernel", ":kernel_sup")
    # kernel keeps this desktop alive, so it cannot be stopped from here...
    assert has_element?(view, "#app-kernel button[phx-click=app_stop][disabled]")
    # ...and the server holds that line even if the button is bypassed.
    render_click(view, "app_stop", %{"name" => "kernel"})
    assert has_element?(view, "#app-kernel .be-tag--warn", "needed by this desktop")
    assert Enum.any?(Application.started_applications(), &match?({:kernel, _, _}, &1))
  end

  test "a library application can be started and stopped from its window", %{conn: conn} do
    # Loaded on the host but not started, and with no processes: starting it
    # only flips a flag in the application controller.
    assert Application.spec(:elixir_make) != nil
    refute Enum.any?(Application.started_applications(), &match?({:elixir_make, _, _}, &1))

    {:ok, view, _html} = live(conn, ~p"/")
    render_click(view, "open", %{"id" => "app-elixir_make"})
    assert has_element?(view, "#app-elixir_make .be-tag", "loaded")

    view |> element("#app-elixir_make button[phx-click=app_start]") |> render_click()
    assert has_element?(view, "#app-elixir_make .be-tag", "started")
    assert Enum.any?(Application.started_applications(), &match?({:elixir_make, _, _}, &1))

    view |> element("#app-elixir_make button[phx-click=app_stop]") |> render_click()
    assert has_element?(view, "#app-elixir_make .be-tag", "loaded")
    refute Enum.any?(Application.started_applications(), &match?({:elixir_make, _, _}, &1))
  end

  test "an open application window is polled until it closes", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_click(view, "open", %{"id" => "app-kernel"})
    assert MapSet.member?(assigns(view).polling, "app-kernel")
    assert %{processes: _} = assigns(view).app_info["app-kernel"]

    send(view.pid, {:poll, "app-kernel"})
    assert MapSet.member?(assigns(view).polling, "app-kernel")

    render_click(view, "close", %{"id" => "app-kernel"})
    send(view.pid, {:poll, "app-kernel"})
    refute MapSet.member?(assigns(view).polling, "app-kernel")
    refute Map.has_key?(assigns(view).app_info, "app-kernel")
    refute has_element?(view, "#app-kernel")
  end

  test "the Resources window meters CPU per core while it is open", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    # Opening starts cpu_sup's measurement window; there is nothing to show yet.
    view |> element("button.be-icon-tile[phx-value-id=resources]") |> render_click()
    assert has_element?(view, "#resources", "measuring")
    assert assigns(view).cpu_read_at != nil

    # Give the window a few clock ticks, then every core has a reading.
    Process.sleep(350)
    send(view.pid, :tick)

    assert %{total: total, cores: [_ | _] = cores} = assigns(view).cpu
    assert total in 0..100
    assert Enum.all?(cores, &(&1.percent in 0..100))
    assert has_element?(view, "#resources .be-core", "cpu0")
    assert has_element?(view, "#resources", "#{length(cores)} cores")

    # Closing forgets the window, so reopening never averages over the gap.
    render_click(view, "close", %{"id" => "resources"})
    send(view.pid, :tick)
    assert assigns(view).cpu_read_at == nil
    assert assigns(view).cpu == %{total: nil, cores: []}
  end

  test "unknown application names render an empty window rather than crashing", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_click(view, "open", %{"id" => "app-no_such_app"})

    assert has_element?(view, "#app-no_such_app", "is not loaded on this node")
  end

  test "the Files window browses the filesystem and knows where it may write", %{conn: conn} do
    dir = files_dir()
    {:ok, view, _html} = live(conn, ~p"/")

    html = view |> element("button.be-icon-tile[phx-value-id=files]") |> render_click()
    assert html =~ "read-only"
    assert has_element?(view, "#files .be-path__crumb[aria-current=location]", "/")
    assert has_element?(view, "#files tr[phx-click=fs_browse][phx-value-path='/tmp']", "tmp")
    assert has_element?(view, "#files button[phx-click=fs_new][disabled]", "New File")

    view |> element("#files tr[phx-value-path='/tmp']") |> render_click()
    assert has_element?(view, "#files .be-path__crumb[aria-current=location]", "tmp")
    assert has_element?(view, "#files .be-tag--ok", "writable")
    refute has_element?(view, "#files button[phx-click=fs_new][disabled]")

    # The Up button goes up, until there is no up.
    view |> element("#files button[aria-label='Up one level']") |> render_click()
    assert has_element?(view, "#files .be-path__crumb[aria-current=location]", "/")
    assert has_element?(view, "#files button[aria-label='Up one level'][disabled]")

    render_click(view, "fs_browse", %{"path" => dir})
    assert has_element?(view, "#files td", "Empty folder")

    # A directory that cannot be read is explained, not crashed on.
    render_click(view, "fs_browse", %{"path" => "/no/such/place"})
    assert has_element?(view, "#files", "no such file or directory")
    assert has_element?(view, "#files button[phx-click=fs_new][disabled]", "New File")

    # Closing forgets the listing; reopening starts over at the root.
    render_click(view, "close", %{"id" => "files"})
    assert assigns(view).files == nil
    render_click(view, "open", %{"id" => "files"})
    assert assigns(view).files.path == "/"
  end

  test "a new file opens in the editor, and Save writes it to disk", %{conn: conn} do
    dir = files_dir()
    {:ok, view, _html} = live(conn, ~p"/")
    render_click(view, "open", %{"id" => "files"})
    render_click(view, "fs_browse", %{"path" => dir})

    view |> element("#files button[phx-value-kind=file]", "New File") |> render_click()
    assert has_element?(view, "#files form input[name=name]")

    view |> form("#files form", %{"name" => "notes.txt"}) |> render_submit()

    path = Path.join(dir, "notes.txt")
    id = file_window_id(:edit, path)
    assert File.read!(path) == ""
    assert has_element?(view, "##{id} textarea[name=text]")
    assert has_element?(view, "##{id}", path)

    assert has_element?(
             view,
             "#files tr[phx-click=fs_open][phx-value-path='#{path}']",
             "notes.txt"
           )

    refute has_element?(view, "#files form")
    assert assigns(view).focused == id

    # Typing is tracked, so a re-render never loses what is on screen...
    view |> form("##{id}-form", %{"text" => "draft"}) |> render_change()
    assert has_element?(view, "##{id} .be-tag--warn", "modified")
    assert File.read!(path) == ""

    # ...and Save writes it, with the browser's line endings straightened out.
    view |> form("##{id}-form", %{"text" => "one\r\ntwo\r\n"}) |> render_submit()
    assert File.read!(path) == "one\ntwo\n"
    assert has_element?(view, "##{id}", "Saved at")
    refute has_element?(view, "##{id} .be-tag--warn")
    assert has_element?(view, "#files tr[phx-value-path='#{path}'] .be-table__num", "8 B")

    # Opening the same file again raises its window rather than re-reading it.
    view |> form("##{id}-form", %{"text" => "unsaved"}) |> render_change()
    render_click(view, "fs_open", %{"path" => path})
    assert assigns(view).editors[id].text == "unsaved"

    # Closing drops the editor and what it held.
    render_click(view, "close", %{"id" => id})
    refute has_element?(view, "##{id}")
    refute Map.has_key?(assigns(view).editors, id)
    assert File.read!(path) == "one\ntwo\n"
  end

  test "a file that is not text gets an alert instead of an editor", %{conn: conn} do
    dir = files_dir()
    path = Path.join(dir, "image.bin")
    File.write!(path, <<0, 1, 2, 255>>)

    {:ok, view, _html} = live(conn, ~p"/")
    render_click(view, "open", %{"id" => "files"})
    render_click(view, "fs_browse", %{"path" => dir})

    view |> element("#files tr[phx-value-path='#{path}']") |> render_click()

    id = file_window_id(:alert, path)
    assert has_element?(view, "##{id}", "There is no viewer for image.bin")
    assert has_element?(view, "##{id}", "not a text file")
    refute Map.has_key?(assigns(view).editors, file_window_id(:edit, path))

    # Opening it again does not stack a second alert.
    render_click(view, "fs_open", %{"path" => path})
    assert map_size(assigns(view).alerts) == 1

    view |> element("##{id} button", "OK") |> render_click()
    refute has_element?(view, "##{id}")
    assert assigns(view).alerts == %{}
  end

  test "nothing is created outside the writable roots, whatever the browser sends", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/")
    render_click(view, "open", %{"id" => "files"})

    # The naming form is not even offered at the root...
    render_click(view, "fs_new", %{"kind" => "file"})
    refute has_element?(view, "#files form")
    assert has_element?(view, "#files", "Files can be created under /data and /tmp")

    # ...and a create sent anyway is refused before it touches the disk.
    render_click(view, "fs_create", %{"kind" => "file", "name" => "hello_live_view_evidence"})
    assert has_element?(view, "#files .be-tag--warn", "read-only")
    refute File.exists?("/hello_live_view_evidence")

    # Nor can a name climb out of a writable folder.
    dir = files_dir()
    render_click(view, "fs_browse", %{"path" => dir})
    render_click(view, "fs_create", %{"kind" => "directory", "name" => "../escape"})
    assert has_element?(view, "#files .be-tag--warn", "not a valid name")
    refute File.exists?(Path.join(dir, "../escape"))
  end

  test "editor windows are restored after a reload, alerts are not", %{conn: conn} do
    dir = files_dir()
    text = Path.join(dir, "readme.txt")
    binary = Path.join(dir, "blob")
    File.write!(text, "kept\n")
    File.write!(binary, <<0, 255>>)

    {:ok, view, _html} = live(conn, ~p"/")
    render_click(view, "fs_open", %{"path" => text})
    render_click(view, "fs_open", %{"path" => binary})
    edit = file_window_id(:edit, text)
    alert = file_window_id(:alert, binary)
    assert has_element?(view, "##{edit}")
    assert has_element?(view, "##{alert}")

    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "##{edit} textarea", "kept")
    refute has_element?(view, "##{alert}")
    refute alert in assigns(view).open

    # A file gone by the next reload takes its window with it.
    File.rm!(text)
    {:ok, view, _html} = live(conn, ~p"/")
    refute has_element?(view, "##{edit}")
    refute edit in assigns(view).open
  end
end
