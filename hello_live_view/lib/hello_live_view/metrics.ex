defmodule HelloLiveView.Metrics do
  @moduledoc """
  What this device keeps a history of, and how the Mobius window reads it.

  [Mobius](https://github.com/mobius-home/mobius) is a metrics library for
  devices that are on their own. It takes `Telemetry.Metrics` definitions,
  scrapes their current values once a second into a round-robin database (the
  last two minutes by the second, two hours by the minute, two days by the
  hour and two months by the day) and persists that under `/data`, so a device
  carries its own recent history across a reboot with no server to send it to.

  `metrics/0` is what Mobius tracks. Most are gauges: the BEAM figures
  `:telemetry_poller` reports out of the box and the device figures
  `measure_device/0` adds from the app's own poller. Three are histograms:
  Mobius keeps a DDSketch of every LiveView event, every render and every
  HTTP request, so the window can answer "how slow is a slow click" with a
  P99 rather than an average. `history/1` reads it all back for the window,
  one entry per metric in `catalog/0`, which is the one place that knows how
  a metric's name maps to a label and a unit.

  Mobius runs as a child of this application's supervisor, so it comes and
  goes with the desktop.
  """

  import Telemetry.Metrics

  alias HelloLiveView.DeviceInfo
  alias Mobius.DDSketch

  @instance :mobius

  # Mobius persists on a clean shutdown, which is how a firmware update or a
  # Restart from the Deskbar ends. Pulling the plug is how a device usually
  # ends, so the history is also written out every few minutes: losing five
  # minutes of samples is nothing, and a write that size on a schedule is
  # nothing to the flash either.
  @autosave_interval 5 * 60

  # Our own measurements go out under this prefix, as [:hello_live_view,
  # :device, :cpu] and so on, which Mobius names "hello_live_view.device.cpu.percent".
  @event [:hello_live_view, :device]

  # How far back the window can look: one entry per resolution of the
  # round-robin database, so each range is exactly what Mobius keeps at that
  # resolution and nothing is shown coarser than it was recorded.
  @ranges [
    minutes: %{label: "2 Minutes", seconds: 2 * 60},
    hours: %{label: "2 Hours", seconds: 2 * 60 * 60},
    days: %{label: "2 Days", seconds: 2 * 24 * 60 * 60},
    months: %{label: "2 Months", seconds: 60 * 24 * 60 * 60}
  ]

  # The percentiles a histogram card reports.
  @quantiles [0.5, 0.95, 0.99]

  # Every duration is a Phoenix `:telemetry.span`, so it arrives in native
  # units. Mobius stores what it is handed, so the conversion happens here
  # and the sketches hold milliseconds. Phoenix does the same in its own
  # Telemetry module with `unit: {:native, :millisecond}`; Mobius leaves
  # `unit` to the reporter, and this is the reporter.
  #
  # The sketch covers 50 µs to 10 s at the default ±10%: a click that takes
  # less is instant, one that takes more has hung, and the five decades
  # between cost about sixty bins per histogram.
  @duration_histogram [
    min_indexable_value: 0.05,
    max_indexable_value: 10_000.0
  ]

  @type range :: :minutes | :hours | :days | :months
  @type unit :: :percent | :bytes | :count | :load | :celsius | :milliseconds

  @typedoc """
  One metric as the window shows it.

  A gauge (`kind: :gauge`) carries `series`, `{unix timestamp, value}` per
  sample in the window, oldest first, with `current` the latest sample and
  `min` and `max` over the series.

  A histogram (`kind: :histogram`) carries the distribution over the window
  instead: `bins` as `{value, count}` ascending, `count` observations in all,
  `quantiles` as `%{0.5 => ms, 0.95 => ms, 0.99 => ms}`, `slowest` and
  `within_budget`, the share of observations under the entry's `budget`, as
  a percentage. Every one of those is nil or empty when nothing was observed.
  """
  @type entry :: map()

  # The catalog, in the order the window lays it out. Gauges are tracked as
  # last_value. The durations are summaries with a histogram, which is
  # Mobius's opt-in for percentiles; the budget is what the card measures
  # the distribution against, and is only a number that reads well.
  @catalog [
    %{
      group: "Device",
      kind: :gauge,
      name: "hello_live_view.device.cpu.percent",
      label: "CPU usage",
      unit: :percent
    },
    %{
      group: "Device",
      kind: :gauge,
      name: "hello_live_view.device.memory.used_percent",
      label: "System memory",
      unit: :percent
    },
    %{
      group: "Device",
      kind: :gauge,
      name: "hello_live_view.device.load.avg1",
      label: "Load average",
      unit: :load
    },
    %{
      group: "Device",
      kind: :gauge,
      name: "hello_live_view.device.temperature.celsius",
      label: "Temperature",
      unit: :celsius
    },
    %{
      group: "Device",
      kind: :gauge,
      name: "hello_live_view.device.storage.used_percent",
      label: "Data partition",
      unit: :percent
    },
    %{group: "BEAM", kind: :gauge, name: "vm.memory.total", label: "Memory", unit: :bytes},
    %{
      group: "BEAM",
      kind: :gauge,
      name: "vm.memory.processes",
      label: "Process heaps",
      unit: :bytes
    },
    %{group: "BEAM", kind: :gauge, name: "vm.memory.binary", label: "Binaries", unit: :bytes},
    %{
      group: "BEAM",
      kind: :gauge,
      name: "vm.system_counts.process_count",
      label: "Processes",
      unit: :count
    },
    %{
      group: "BEAM",
      kind: :gauge,
      name: "vm.system_counts.atom_count",
      label: "Atoms",
      unit: :count
    },
    %{
      group: "BEAM",
      kind: :gauge,
      name: "vm.total_run_queue_lengths.total",
      label: "Run queue",
      unit: :count
    },
    %{
      group: "Phoenix",
      kind: :histogram,
      name: "phoenix.live_view.handle_event.stop.duration",
      label: "LiveView events",
      unit: :milliseconds,
      budget: 50
    },
    %{
      group: "Phoenix",
      kind: :histogram,
      name: "phoenix.live_view.render.stop.duration",
      label: "LiveView renders",
      unit: :milliseconds,
      budget: 16
    },
    %{
      group: "Phoenix",
      kind: :histogram,
      name: "phoenix.endpoint.stop.duration",
      label: "HTTP requests",
      unit: :milliseconds,
      budget: 200
    }
  ]

  # ------------------------------------------------------------ supervision

  @doc """
  The Mobius child for the application's supervision tree, configured with
  `metrics/0` and this app's data directory.
  """
  @spec child_spec(term()) :: Supervisor.child_spec()
  def child_spec(_opts) do
    Supervisor.child_spec(
      {Mobius,
       mobius_instance: @instance,
       metrics: metrics(),
       persistence_dir: HelloLiveView.data_dir(),
       autosave_interval: @autosave_interval},
      []
    )
  end

  @doc "Where Mobius writes its history, metrics table and event log."
  @spec persistence_dir() :: String.t()
  def persistence_dir, do: Path.join(HelloLiveView.data_dir(), to_string(@instance))

  @doc "The `Telemetry.Metrics` definitions Mobius tracks, one per catalog entry."
  @spec metrics() :: [Telemetry.Metrics.t()]
  def metrics do
    for entry <- @catalog, do: metric(entry.kind, entry.name)
  end

  defp metric(:gauge, name), do: last_value(name)

  defp metric(:histogram, name) do
    summary(name,
      measurement: &milliseconds/1,
      reporter_options: [histogram: @duration_histogram]
    )
  end

  @doc false
  # Public so a test can hand Mobius a duration the way Phoenix does.
  @spec milliseconds(%{duration: integer()}) :: float()
  def milliseconds(%{duration: native}),
    do: System.convert_time_unit(native, :native, :microsecond) / 1000

  @doc "The metrics the window shows, in order, without any data."
  @spec catalog() :: [map()]
  def catalog, do: @catalog

  # ------------------------------------------------------------- measuring

  @doc """
  Report the device's own figures as telemetry events, one per reading:

    * `[:hello_live_view, :device, :cpu]` — `%{percent: 0..100}`
    * `[:hello_live_view, :device, :memory]` — `%{used_percent:, used_mb:, size_mb:}`
    * `[:hello_live_view, :device, :load]` — `%{avg1:, avg5:, avg15:}`
    * `[:hello_live_view, :device, :temperature]` — `%{celsius:}`
    * `[:hello_live_view, :device, :storage]` — `%{used_percent:, used_mb:, size_mb:}`

  Run by the app's `:telemetry_poller` every few seconds. A reading the
  platform cannot give (no thermal zone on the host, no cpu_sup on an OS
  os_mon does not know) is simply not reported, so the metric has no
  samples rather than fake ones. CPU usage is measured since the poller's
  last reading, so it is the average over one poll interval.
  """
  @spec measure_device() :: :ok
  def measure_device do
    report(:cpu, cpu())
    report(:memory, memory())
    report(:load, DeviceInfo.load())
    report(:temperature, temperature())
    report(:storage, storage())
    :ok
  end

  defp report(_what, nil), do: :ok
  defp report(what, measurements), do: :telemetry.execute(@event ++ [what], measurements, %{})

  defp cpu do
    case DeviceInfo.cpu() do
      %{total: percent} when is_integer(percent) -> %{percent: percent}
      _unsupported -> nil
    end
  end

  defp memory do
    case DeviceInfo.memory() do
      %{system: {:ok, stats}} -> Map.take(stats, [:used_percent, :used_mb, :size_mb])
      _no_memsup -> nil
    end
  end

  defp temperature do
    case DeviceInfo.temperature() do
      celsius when is_number(celsius) -> %{celsius: celsius}
      nil -> nil
    end
  end

  defp storage do
    case DeviceInfo.storage() do
      %{used_percent: _} = stats -> Map.take(stats, [:used_percent, :used_mb, :size_mb])
      nil -> nil
    end
  end

  # --------------------------------------------------------------- reading

  @doc "The ranges the window can show, as `{range, label}` in menu order."
  @spec ranges() :: [{range(), String.t()}]
  def ranges, do: for({range, %{label: label}} <- @ranges, do: {range, label})

  @doc "The default range: the last two hours, at a sample a minute."
  @spec default_range() :: range()
  def default_range, do: :hours

  @doc "A range from the wire, without creating atoms from user input."
  @spec fetch_range(String.t()) :: {:ok, range()} | :error
  def fetch_range(string) when is_binary(string) do
    Enum.find_value(@ranges, :error, fn {range, _opts} ->
      if Atom.to_string(range) == string, do: {:ok, range}
    end)
  end

  @doc """
  Every catalog metric with what was recorded over the last `range`, grouped
  the way the window lays them out:

      %{range: :hours, label: "2 Hours", from: 1725630000, to: 1725637200,
        groups: [%{title: "Device", metrics: [entry, ...]}, ...]}

  `from` and `to` are the unix seconds the samples were asked for, so a chart
  can place them in time rather than just in order: after a reboot the
  samples come back as dense as they were kept, with a gap where the device
  was off. While Mobius is down every entry is simply empty.
  """
  @spec history(range()) :: %{
          range: range(),
          label: String.t(),
          from: integer(),
          to: integer(),
          groups: [%{title: String.t(), metrics: [entry()]}]
        }
  def history(range) do
    %{seconds: seconds, label: label} = Keyword.fetch!(@ranges, range)
    to = System.system_time(:second)
    from = to - seconds
    opts = [mobius_instance: @instance, from: from, to: to]

    groups =
      @catalog
      |> Enum.map(&describe(&1.kind, &1, opts))
      |> Enum.chunk_by(& &1.group)
      |> Enum.map(&%{title: hd(&1).group, metrics: &1})

    %{range: range, label: label, from: from, to: to, groups: groups}
  end

  @doc """
  Write the history to disk now rather than at the next autosave. Handy just
  before pulling the plug.
  """
  @spec save() :: :ok | {:error, term()}
  def save do
    Mobius.save(@instance)
  catch
    :exit, _not_running -> {:error, :not_running}
  end

  defp describe(:gauge, entry, opts) do
    series =
      case Mobius.Charts.series(entry.name, :last_value, %{}, opts) do
        {:ok, %{points: points}} -> for %{timestamp: ts, value: value} <- points, do: {ts, value}
        {:error, _unavailable} -> []
      end

    values = Enum.map(series, &elem(&1, 1))

    Map.merge(entry, %{
      series: series,
      current: List.last(values),
      min: Enum.min(values, fn -> nil end),
      max: Enum.max(values, fn -> nil end)
    })
  end

  # One sketch per window answers everything on the card. It is rebuilt from
  # the snapshots at both ends of the window, so a two-month distribution
  # costs the same as a two-minute one.
  defp describe(:histogram, entry, opts) do
    sketch =
      case Mobius.Data.histogram(entry.name, %{}, opts) do
        {:ok, sketch} -> sketch
        {:error, _unavailable} -> nil
      end

    count = if sketch, do: DDSketch.total_count(sketch), else: 0

    if count == 0 do
      Map.merge(entry, %{bins: [], count: 0, quantiles: %{}, slowest: nil, within_budget: nil})
    else
      Map.merge(entry, %{
        bins: DDSketch.bin_estimates(sketch),
        count: count,
        quantiles: DDSketch.quantiles(sketch, @quantiles),
        slowest: DDSketch.max(sketch),
        within_budget: round(DDSketch.count_below(sketch, entry.budget) / count * 100)
      })
    end
  end
end
