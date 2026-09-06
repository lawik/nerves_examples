defmodule HelloLiveView.GPIO do
  @moduledoc """
  The device's GPIO lines, in a shape the desktop can show and poke.

  `Circuits.GPIO` does the real work. This module adds what a window needs on
  top of it: a stable string id for every line (`"gpiochip0-4"`), so a click
  can name one without the page ever seeing a tuple, and a small record for
  an open line that carries its handle, direction, pull and last known level.

  A line is always opened as an input first, which never drives anything the
  board might not like. Direction, pull and output level are then changed
  through the handle. An open input also subscribes to change notifications,
  so a button press arrives in the owning process as a `{:circuits_gpio, ...}`
  message that `on_change/2` folds into the record; nobody has to poll to see
  a level change.

  On the host there is no GPIO hardware and `Circuits.GPIO` falls back to its
  stub backend: 64 simulated lines wired in pairs (0 to 1, 2 to 3, and so on),
  so what one drives the other reads. `simulated?/0` says when that is the
  case.
  """

  alias Circuits.GPIO

  @type id :: String.t()
  @type direction :: :input | :output
  @type pull :: :none | :pullup | :pulldown
  @type level :: 0 | 1

  @type line :: %{
          id: id(),
          name: String.t(),
          location: {String.t(), non_neg_integer()},
          consumer: String.t() | nil,
          free?: boolean()
        }

  @type open :: %{
          line: line(),
          handle: GPIO.Handle.t(),
          direction: direction(),
          pull: pull(),
          value: level()
        }

  @doc "Every line the controllers expose, sorted by controller and offset."
  @spec list() :: [line()]
  def list do
    GPIO.enumerate()
    |> Enum.map(&describe/1)
    |> Enum.sort_by(& &1.location)
  end

  @doc "Resolve an id from the wire to a line, or `:error` if there is no such line."
  @spec fetch(id()) :: {:ok, line()} | :error
  def fetch(id) when is_binary(id) do
    case Enum.find(list(), &(&1.id == id)) do
      nil -> :error
      line -> {:ok, line}
    end
  end

  @doc "Whether the lines are the stub backend's rather than real hardware."
  @spec simulated?() :: boolean()
  def simulated? do
    case GPIO.backend_info() do
      %{name: {_backend, options}} when is_list(options) -> Keyword.get(options, :test, false)
      _other -> false
    end
  end

  @doc """
  Open a line as an input and subscribe to its changes.

  The calling process owns the handle: it receives the notifications, and the
  line is released when the process exits should `close/1` never run.
  """
  @spec open(line()) :: {:ok, open()} | {:error, term()}
  def open(line) do
    with {:ok, handle} <- GPIO.open(line.location, :input) do
      {:ok, subscribe(%{line: line, handle: handle, direction: :input, pull: :none, value: 0})}
    end
  end

  @doc "Release a line."
  @spec close(open()) :: :ok
  def close(open), do: GPIO.close(open.handle)

  @doc "Re-read an input's level. An output's is whatever was last written."
  @spec refresh(open()) :: open()
  def refresh(%{direction: :input} = open), do: %{open | value: GPIO.read(open.handle)}
  def refresh(open), do: open

  @doc "Switch a line between input and output. An output starts low."
  @spec set_direction(open(), direction()) :: {:ok, open()} | {:error, term()}
  def set_direction(%{direction: direction} = open, direction), do: {:ok, open}

  def set_direction(open, :output) do
    # Edge detection belongs to inputs, so stop listening before the switch.
    _ = GPIO.unsubscribe(open.handle)

    with :ok <- GPIO.set_direction(open.handle, :output),
         :ok <- GPIO.write(open.handle, 0) do
      {:ok, %{open | direction: :output, value: 0}}
    else
      {:error, reason} ->
        # Still an input, so go on listening to it.
        _ = subscribe(open)
        {:error, reason}
    end
  end

  def set_direction(open, :input) do
    with :ok <- GPIO.set_direction(open.handle, :input) do
      {:ok, subscribe(%{open | direction: :input})}
    end
  end

  @doc "Set an input's internal pull resistor."
  @spec set_pull(open(), pull()) :: {:ok, open()} | {:error, term()}
  def set_pull(%{direction: :input} = open, pull) do
    with :ok <- GPIO.set_pull_mode(open.handle, pull) do
      {:ok, refresh(%{open | pull: pull})}
    end
  end

  def set_pull(_open, _pull), do: {:error, :not_an_input}

  @doc "Drive an output high or low."
  @spec write(open(), level()) :: {:ok, open()} | {:error, term()}
  def write(%{direction: :output} = open, level) when level in [0, 1] do
    with :ok <- GPIO.write(open.handle, level), do: {:ok, %{open | value: level}}
  end

  def write(_open, _level), do: {:error, :not_an_output}

  @doc """
  Fold a change notification into the open line it is about.

  Subscriptions are tagged with the line's id, so the notification names the
  line itself and nothing else has to know what the message looks like. A
  late notification for a line that has since become an output is ignored.
  """
  @spec on_change(%{id() => open()}, map()) :: %{id() => open()}
  def on_change(opens, %{ref: id, value: level}) when is_map_key(opens, id) do
    case opens[id] do
      %{direction: :input} = open -> Map.put(opens, id, %{open | value: level})
      _output -> opens
    end
  end

  def on_change(opens, _notification), do: opens

  # -------------------------------------------------------------- the wire

  @doc "A direction as named on the wire."
  @spec direction(String.t()) :: {:ok, direction()} | :error
  def direction("input"), do: {:ok, :input}
  def direction("output"), do: {:ok, :output}
  def direction(_other), do: :error

  @doc "A pull mode as named on the wire."
  @spec pull(String.t()) :: {:ok, pull()} | :error
  def pull("none"), do: {:ok, :none}
  def pull("pullup"), do: {:ok, :pullup}
  def pull("pulldown"), do: {:ok, :pulldown}
  def pull(_other), do: :error

  @doc "A level as named on the wire."
  @spec level(String.t()) :: {:ok, level()} | :error
  def level("0"), do: {:ok, 0}
  def level("1"), do: {:ok, 1}
  def level(_other), do: :error

  # ---------------------------------------------------------------- helpers

  defp subscribe(open) do
    _ = GPIO.subscribe(open.handle, tag: open.line.id)
    refresh(open)
  end

  # `free?` is advisory: a line another process holds says so here, but only
  # `open/1` can tell for sure, so a line whose status cannot be read is
  # offered rather than hidden.
  defp describe(%{location: {controller, offset} = location, label: label}) do
    id = "#{controller}-#{offset}"

    {consumer, free?} =
      case GPIO.status(location) do
        {:ok, %{consumer: ""}} -> {nil, true}
        {:ok, %{consumer: consumer}} -> {consumer, false}
        {:error, _reason} -> {nil, true}
      end

    %{id: id, name: name(label, offset), location: location, consumer: consumer, free?: free?}
  end

  # Device trees name the lines worth naming ("GPIO4", "ID_SD"); the rest
  # come back as "" or "-".
  defp name(label, offset) when label in ["", "-", nil], do: "line #{offset}"
  defp name(label, _offset), do: label
end
