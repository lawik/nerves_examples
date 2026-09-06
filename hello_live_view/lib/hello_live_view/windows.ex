defmodule HelloLiveView.Windows do
  @moduledoc """
  Persistent windowing state: which windows are open, where they sit and how
  they stack.

  The state lives in a `:dets` table under `/data`, the writable partition on a
  Nerves device, so a window you dragged somewhere is still there after a
  reboot or a firmware update. On the host, where `/data` does not exist, it
  falls back to a directory under `System.tmp_dir!/0` so `mix phx.server`
  behaves the same way.

  This module owns *state only* — position, stacking and open/closed. What a
  window is called and what it renders belongs to the LiveView, so adding a new
  window never means touching persistence or migrating the table.

  Every mutation is synced to disk before the call returns. That matters more
  than it looks: an embedded device is usually switched off by pulling the
  power, and an unsynced `:dets` table does not merely log "not properly
  closed, repairing" on the next boot — the repair *discards* the unwritten
  records. Since these writes are human-paced (one per pointer-up, one per
  click) the flash cost is irrelevant next to silently losing the layout.
  """

  use GenServer

  require Logger

  @table :hello_live_view_windows
  @auto_save_interval :timer.seconds(30)

  # Cascade offsets for a window that has never been placed, so two windows
  # opened in a row don't land exactly on top of each other.
  # Clear of the desktop icon rail on the left (8px + 84px wide).
  @cascade_origin {116, 28}
  @cascade_step 28
  @cascade_positions 6

  @type id :: String.t()
  @type window :: %{
          id: id(),
          open?: boolean(),
          zoomed?: boolean(),
          x: non_neg_integer(),
          y: non_neg_integer(),
          z: pos_integer(),
          w: pos_integer() | nil,
          h: pos_integer() | nil
        }

  # A window sizes itself to its content until someone drags the resize grip;
  # from then on it keeps the size it was given. `nil` means "not yet sized".
  @unsized %{w: nil, h: nil}
  @min_width 260
  @min_height 140

  # ------------------------------------------------------------------- client

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Every window we have state for, keyed by id."
  @spec all() :: %{id() => window()}
  def all, do: GenServer.call(__MODULE__, :all)

  @doc "Open a window, placing it if it has never been placed, and raise it."
  @spec open(id()) :: %{id() => window()}
  def open(id), do: GenServer.call(__MODULE__, {:open, id})

  @doc "Close a window. Its position is kept for the next time it opens."
  @spec close(id()) :: %{id() => window()}
  def close(id), do: GenServer.call(__MODULE__, {:close, id})

  @doc "Bring a window to the front."
  @spec raise_window(id()) :: %{id() => window()}
  def raise_window(id), do: GenServer.call(__MODULE__, {:raise, id})

  @doc "Move a window to a desktop coordinate. Also raises it."
  @spec move(id(), integer(), integer()) :: %{id() => window()}
  def move(id, x, y), do: GenServer.call(__MODULE__, {:move, id, x, y})

  @doc """
  Resize a window. Also raises it, since you were just holding onto it.

  Sizes are clamped to a usable minimum so a window can never be shrunk to a
  sliver you cannot grab again.
  """
  @spec resize(id(), integer(), integer()) :: %{id() => window()}
  def resize(id, width, height), do: GenServer.call(__MODULE__, {:resize, id, width, height})

  @doc "Toggle a window between its placed size and full desktop width."
  @spec toggle_zoom(id()) :: %{id() => window()}
  def toggle_zoom(id), do: GenServer.call(__MODULE__, {:toggle_zoom, id})

  @doc "Forget everything. Handy from the IEx prompt on a device."
  @spec reset() :: %{id() => window()}
  def reset, do: GenServer.call(__MODULE__, :reset)

  @doc "Where the table is stored — `/data` on a device, a temp dir on the host."
  @spec data_dir() :: String.t()
  def data_dir do
    Application.get_env(:hello_live_view, :data_dir) ||
      if File.dir?("/data"),
        do: "/data",
        else: Path.join(System.tmp_dir!(), "hello_live_view")
  end

  # ------------------------------------------------------------------- server

  @impl GenServer
  def init(_opts) do
    Process.flag(:trap_exit, true)

    dir = data_dir()
    File.mkdir_p!(dir)
    path = dir |> Path.join("windows.dets") |> String.to_charlist()

    case :dets.open_file(@table, file: path, type: :set, auto_save: @auto_save_interval) do
      {:ok, @table} ->
        {:ok, %{table: @table}}

      {:error, reason} ->
        # A corrupt table should not stop the device from booting. Start over
        # with default placement rather than crashing the supervision tree.
        Logger.warning("windows: could not open #{path}: #{inspect(reason)}; starting fresh")
        File.rm(path)
        {:ok, @table} = :dets.open_file(@table, file: path, type: :set)
        {:ok, %{table: @table}}
    end
  end

  @impl GenServer
  def handle_call(:all, _from, state), do: {:reply, load(state.table), state}

  def handle_call({:open, id}, _from, state) do
    windows = load(state.table)

    window =
      windows
      |> Map.get_lazy(id, fn -> place_new(id, windows) end)
      |> Map.put(:open?, true)

    {:reply, commit(state.table, put_and_raise(state.table, windows, window)), state}
  end

  def handle_call({:close, id}, _from, state) do
    windows = load(state.table)

    case Map.fetch(windows, id) do
      # Position and zoom survive the close, so reopening puts it back where it was.
      {:ok, w} ->
        {:reply, commit(state.table, put(state.table, windows, %{w | open?: false})), state}

      :error ->
        {:reply, windows, state}
    end
  end

  def handle_call({:raise, id}, _from, state) do
    windows = load(state.table)

    case Map.fetch(windows, id) do
      {:ok, w} -> {:reply, commit(state.table, put_and_raise(state.table, windows, w)), state}
      :error -> {:reply, windows, state}
    end
  end

  def handle_call({:move, id, x, y}, _from, state) do
    windows = load(state.table)

    case Map.fetch(windows, id) do
      {:ok, window} ->
        moved = %{window | x: max(x, 0), y: max(y, 0)}
        {:reply, commit(state.table, put_and_raise(state.table, windows, moved)), state}

      :error ->
        {:reply, windows, state}
    end
  end

  def handle_call({:resize, id, width, height}, _from, state) do
    windows = load(state.table)

    case Map.fetch(windows, id) do
      {:ok, window} ->
        sized = %{window | w: max(width, @min_width), h: max(height, @min_height)}
        {:reply, commit(state.table, put_and_raise(state.table, windows, sized)), state}

      :error ->
        {:reply, windows, state}
    end
  end

  def handle_call({:toggle_zoom, id}, _from, state) do
    windows = load(state.table)

    case Map.fetch(windows, id) do
      {:ok, window} ->
        zoomed = %{window | zoomed?: not window.zoomed?}
        {:reply, commit(state.table, put_and_raise(state.table, windows, zoomed)), state}

      :error ->
        {:reply, windows, state}
    end
  end

  def handle_call(:reset, _from, state) do
    :dets.delete_all_objects(state.table)
    :dets.sync(state.table)
    {:reply, %{}, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    # The one place a sync is worth it: flush before the table closes.
    :dets.sync(state.table)
    :dets.close(state.table)
    :ok
  end

  # ------------------------------------------------------------------ storage

  defp load(table) do
    table
    |> :dets.match_object({:_, :_})
    |> Map.new(fn {id, window} -> {id, Map.merge(@unsized, window)} end)
  end

  defp put(table, windows, window) do
    :dets.insert(table, {window.id, window})
    Map.put(windows, window.id, window)
  end

  # One flush per mutation, after all the records for it are in.
  defp commit(table, windows) do
    :dets.sync(table)
    windows
  end

  # Raising renumbers every open window from 1..n instead of incrementing a
  # counter forever, which keeps z-index values small and readable in devtools.
  defp put_and_raise(table, windows, window) do
    windows = Map.put(windows, window.id, window)

    ordered =
      windows
      |> Map.values()
      |> Enum.sort_by(&{&1.id == window.id, &1.z})

    ordered
    |> Enum.with_index(1)
    |> Enum.reduce(windows, fn {w, z}, acc -> put(table, acc, %{w | z: z}) end)
  end

  defp place_new(id, windows) do
    {origin_x, origin_y} = @cascade_origin
    step = rem(map_size(windows), @cascade_positions) * @cascade_step

    Map.merge(@unsized, %{
      id: id,
      open?: false,
      zoomed?: false,
      x: origin_x + step,
      y: origin_y + step,
      z: 1
    })
  end
end
