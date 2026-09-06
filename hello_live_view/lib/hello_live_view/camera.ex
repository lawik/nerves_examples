defmodule HelloLiveView.Camera do
  @moduledoc """
  Keeps the latest still from a security camera, for the desktop's window
  and for whoever asks over HTTP.

  One camera per device, watched from `watch/3` until `stop/0`. Every five
  seconds a snapshot is fetched and replaces the one before it, so there is
  never more than one in memory and no still goes to disk. Each fetch runs
  in its own task, so a camera that takes its time never blocks the process
  that hands out the image, and a fetch still running when the next beat
  comes is left to finish and that beat is skipped.

  The address and login are saved next to the window layout, `/data` on a
  device (see `HelloLiveView.Windows.data_dir/0`), so a watched camera is
  watched again after a reboot; `stop/0` removes them. The password is in
  that file as typed, readable by whoever can read the data partition,
  which on a Nerves device is root.

  Nothing here raises at the person on the screen. A camera that cannot be
  reached, a login it refuses, a file that cannot be written or read back:
  each becomes a sentence in the status, and the process carries on.

  Every change, a new still, an error, a stop, is broadcast on the `"camera"`
  PubSub topic as `{:camera, status}`, which is what the window listens for.
  `HelloLiveViewWeb.CameraController` serves the bytes.

  The fetch itself is `HelloLiveView.Milesight.snapshot/3`, unless the
  `:camera_fetch` application setting names another `{module, function}`,
  which is how the tests stand in a camera.
  """

  use GenServer

  require Logger

  alias HelloLiveView.Milesight
  alias HelloLiveView.Windows

  @interval 5_000
  @topic "camera"
  @pubsub HelloLiveView.PubSub
  @tasks HelloLiveView.TaskSupervisor
  @settings_file "camera.config"

  @type status :: %{
          running?: boolean(),
          fetching?: boolean(),
          host: String.t() | nil,
          user: String.t() | nil,
          taken_at: DateTime.t() | nil,
          bytes: non_neg_integer() | nil,
          error: String.t() | nil
        }

  @doc """
  Options: `:name` (this module; nil for an unnamed instance), `:path` for
  the settings file, `:fetch` as `{module, function}`.
  """
  def start_link(opts \\ []) do
    case Keyword.get(opts, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @doc "Start watching a camera, replacing whatever was watched, and remember it."
  @spec watch(GenServer.server(), String.t(), String.t(), String.t()) :: :ok
  def watch(server \\ __MODULE__, host, user, password),
    do: GenServer.call(server, {:watch, host, user, password})

  @doc "Stop watching, drop the last still and forget the settings."
  @spec stop(GenServer.server()) :: :ok
  def stop(server \\ __MODULE__), do: GenServer.call(server, :stop)

  @spec status(GenServer.server()) :: status()
  def status(server \\ __MODULE__), do: GenServer.call(server, :status)

  @doc "The latest still and when it was taken."
  @spec latest(GenServer.server()) :: {:ok, binary(), DateTime.t()} | :error
  def latest(server \\ __MODULE__), do: GenServer.call(server, :latest)

  @doc "Have `{:camera, status}` sent here on every change."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(@pubsub, @topic)

  @spec unsubscribe() :: :ok
  def unsubscribe, do: Phoenix.PubSub.unsubscribe(@pubsub, @topic)

  @doc "Where the settings are kept."
  @spec config_path() :: String.t()
  def config_path, do: Path.join(Windows.data_dir(), @settings_file)

  # ------------------------------------------------------------------ server

  @impl true
  def init(opts) do
    fetch =
      Keyword.get(opts, :fetch) ||
        Application.get_env(:hello_live_view, :camera_fetch, {Milesight, :snapshot})

    state = %{
      camera: nil,
      latest: nil,
      error: nil,
      timer: nil,
      task: nil,
      fetch: fetch,
      path: Keyword.get(opts, :path) || config_path()
    }

    case read_settings(state.path) do
      {:ok, nil} ->
        {:ok, state}

      {:ok, camera} ->
        send(self(), :tick)
        {:ok, %{state | camera: camera}}

      {:error, message} ->
        Logger.warning("camera: #{message}")
        {:ok, %{state | error: message}}
    end
  end

  @impl true
  def handle_call({:watch, host, user, password}, _from, state) do
    camera = %{host: host, user: user, password: password}
    state = state |> cancel() |> drop_task()
    state = %{state | camera: camera, latest: nil, error: save_settings(state.path, camera)}
    send(self(), :tick)
    {:reply, :ok, broadcast(state)}
  end

  def handle_call(:stop, _from, state) do
    state = state |> cancel() |> drop_task()
    state = %{state | camera: nil, latest: nil, error: remove_settings(state.path)}
    {:reply, :ok, broadcast(state)}
  end

  def handle_call(:status, _from, state), do: {:reply, report(state), state}

  def handle_call(:latest, _from, %{latest: {jpeg, taken_at}} = state),
    do: {:reply, {:ok, jpeg, taken_at}, state}

  def handle_call(:latest, _from, state), do: {:reply, :error, state}

  @impl true
  def handle_info(:tick, %{camera: nil} = state), do: {:noreply, state}

  def handle_info(:tick, state) do
    state = %{state | timer: Process.send_after(self(), :tick, @interval)}

    if state.task do
      {:noreply, state}
    else
      %{host: host, user: user, password: password} = state.camera
      {mod, fun} = state.fetch

      task =
        Task.Supervisor.async_nolink(@tasks, fn -> apply(mod, fun, [host, user, password]) end)

      {:noreply, broadcast(%{state | task: task.ref})}
    end
  end

  def handle_info({ref, result}, %{task: ref} = state) do
    Process.demonitor(ref, [:flush])

    state =
      case result do
        {:ok, jpeg} -> %{state | latest: {jpeg, DateTime.utc_now()}, error: nil}
        {:error, reason} -> %{state | error: describe(reason)}
        other -> %{state | error: "the camera gave an unexpected answer: #{inspect(other)}"}
      end

    {:noreply, broadcast(%{state | task: nil})}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{task: ref} = state) do
    {:noreply, broadcast(%{state | task: nil, error: "the fetch crashed: #{inspect(reason)}"})}
  end

  # A result from a fetch that outlived its camera, or anything else.
  def handle_info(_message, state), do: {:noreply, state}

  # ---------------------------------------------------------------- settings

  defp read_settings(path) do
    case File.read(path) do
      {:ok, binary} ->
        decode_settings(binary)

      {:error, :enoent} ->
        {:ok, nil}

      {:error, reason} ->
        {:error, "the saved camera settings could not be read: #{file_error(reason)}"}
    end
  end

  defp decode_settings(binary) do
    case :erlang.binary_to_term(binary, [:safe]) do
      %{host: host, user: user, password: password}
      when is_binary(host) and is_binary(user) and is_binary(password) ->
        {:ok, %{host: host, user: user, password: password}}

      _other ->
        {:error, "the saved camera settings made no sense and were left alone"}
    end
  rescue
    ArgumentError ->
      {:error, "the saved camera settings could not be decoded and were left alone"}
  end

  # nil when saved; otherwise what to tell the person, since the camera is
  # watched either way.
  defp save_settings(path, camera) do
    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, :erlang.term_to_binary(camera)) do
      nil
    else
      {:error, reason} ->
        "the camera is watched, but the settings could not be saved: #{file_error(reason)}"
    end
  end

  defp remove_settings(path) do
    case File.rm(path) do
      :ok -> nil
      {:error, :enoent} -> nil
      {:error, reason} -> "the saved camera settings could not be removed: #{file_error(reason)}"
    end
  end

  defp file_error(reason), do: reason |> :file.format_error() |> to_string()

  # ----------------------------------------------------------------- helpers

  defp cancel(%{timer: nil} = state), do: state

  defp cancel(state) do
    Process.cancel_timer(state.timer)
    %{state | timer: nil}
  end

  # A fetch still running belongs to the camera being left behind.
  defp drop_task(%{task: nil} = state), do: state

  defp drop_task(state) do
    Process.demonitor(state.task, [:flush])
    %{state | task: nil}
  end

  defp broadcast(state) do
    Phoenix.PubSub.broadcast(@pubsub, @topic, {:camera, report(state)})
    state
  end

  defp report(state) do
    %{
      running?: state.camera != nil,
      fetching?: state.task != nil,
      host: state.camera && state.camera.host,
      user: state.camera && state.camera.user,
      taken_at: state.latest && elem(state.latest, 1),
      bytes: state.latest && byte_size(elem(state.latest, 0)),
      error: state.error
    }
  end

  defp describe(:unauthorized), do: "the camera refused that user or password"
  defp describe(:timeout), do: "the camera did not answer in time"
  defp describe({:failed_connect, _details}), do: "could not connect to the camera"
  defp describe({:http, status}), do: "the camera answered with HTTP #{status}"
  defp describe(:not_an_image), do: "the camera did not send an image"

  defp describe({:unsupported_authentication, scheme}),
    do: "the camera wants #{scheme} authentication, which is not supported"

  defp describe({:unsupported_algorithm, algorithm}),
    do: "the camera wants #{algorithm} digests, which is not supported"

  defp describe(reason), do: "the fetch failed: #{inspect(reason)}"
end
