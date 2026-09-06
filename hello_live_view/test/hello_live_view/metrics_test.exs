defmodule HelloLiveView.MetricsTest do
  # Everything here reads the one Mobius instance the application starts.
  use ExUnit.Case, async: false

  alias HelloLiveView.Metrics

  # The render span has no logger handler of its own, so it can be reported
  # here with empty metadata; the handle_event span's would crash on it.
  @histogram "phoenix.live_view.render.stop.duration"

  # Mobius scrapes the current values into its history once a second.
  defp eventually(fun, attempts \\ 60) do
    cond do
      fun.() -> true
      attempts == 0 -> false
      true -> Process.sleep(50) && eventually(fun, attempts - 1)
    end
  end

  defp entry(range, name) do
    for(group <- Metrics.history(range).groups, metric <- group.metrics, do: metric)
    |> Enum.find(&(&1.name == name))
  end

  test "every catalog entry is tracked, the durations as histograms" do
    metrics = Metrics.metrics()

    assert Enum.map(metrics, &Enum.join(&1.name, ".")) == Enum.map(Metrics.catalog(), & &1.name)

    summaries = for %Telemetry.Metrics.Summary{} = metric <- metrics, do: metric

    assert Enum.map(summaries, &Enum.join(&1.name, ".")) ==
             for(entry <- Metrics.catalog(), entry.kind == :histogram, do: entry.name)

    assert Enum.all?(summaries, &Keyword.keyword?(&1.reporter_options[:histogram]))

    # And Mobius agrees, so the sketches are actually being kept.
    assert Enum.count(Mobius.Charts.list_metrics(), & &1.histogram?) == length(summaries)
  end

  test "measure_device/0 reports what this platform can measure, as events" do
    parent = self()

    events =
      for what <- [:cpu, :memory, :load, :temperature, :storage],
          do: [:hello_live_view, :device, what]

    :telemetry.attach_many(
      "metrics-test",
      events,
      fn event, measurements, _meta, _config -> send(parent, {:device, event, measurements}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach("metrics-test") end)

    assert Metrics.measure_device() == :ok

    assert_receive {:device, [:hello_live_view, :device, :memory], %{used_percent: used}}
    assert used in 0..100
    assert_receive {:device, [:hello_live_view, :device, :load], %{avg1: avg1}}
    assert is_float(avg1)

    assert_receive {:device, [:hello_live_view, :device, :storage],
                    %{used_percent: _, size_mb: _}}

    if HelloLiveView.DeviceInfo.cpu_supported?() do
      assert_receive {:device, [:hello_live_view, :device, :cpu], %{percent: percent}}
      assert percent in 0..100
    end
  end

  test "history/1 has an entry per metric, placed in the range asked for" do
    # What :telemetry_poller's own poller reports every few seconds, reported
    # now so the test need not wait for it; the scraper notices within a second.
    :telemetry.execute([:vm, :memory], Map.new(:erlang.memory()), %{})
    assert eventually(fn -> entry(:minutes, "vm.memory.total").series != [] end)

    history = Metrics.history(:minutes)
    assert history.label == "2 Minutes"
    assert history.to - history.from == 120
    assert Enum.map(history.groups, & &1.title) == ["Device", "BEAM", "Phoenix"]

    names = for group <- history.groups, metric <- group.metrics, do: metric.name
    assert names == Enum.map(Metrics.catalog(), & &1.name)

    memory = entry(:minutes, "vm.memory.total")
    assert memory.kind == :gauge
    assert [{ts, bytes} | _] = memory.series
    assert ts in history.from..history.to
    assert bytes > 0
    assert memory.current == memory.series |> List.last() |> elem(1)
    assert memory.min <= memory.current and memory.current <= memory.max
  end

  test "a histogram entry answers with percentiles over the range" do
    # The history persisted by an earlier run is loaded at boot and other
    # tests click around the desktop, so the sketch is never empty or ours
    # alone. The widest range holds everything retained, so what is asserted
    # is what these observations add to it.
    before = entry(:months, @histogram).count

    # Durations the way Phoenix reports them: native units, in a span.
    for ms <- [1, 2, 3, 4, 100] do
      :telemetry.execute(
        [:phoenix, :live_view, :render, :stop],
        %{duration: System.convert_time_unit(ms, :millisecond, :native)},
        %{}
      )
    end

    assert eventually(fn -> entry(:months, @histogram).count >= before + 5 end)

    renders = entry(:months, @histogram)
    assert renders.kind == :histogram
    assert %{0.5 => p50, 0.95 => p95, 0.99 => p99} = renders.quantiles
    assert p50 <= p95 and p95 <= p99
    # The 100 ms one is in there, give or take the sketch's ten percent.
    assert renders.slowest >= 90
    assert renders.within_budget in 0..100
    assert [{_value, _count} | _] = renders.bins
    assert renders.bins == Enum.sort_by(renders.bins, &elem(&1, 0))

    # The narrower ranges are cut from the same snapshots, so they hold no
    # more than the whole.
    assert entry(:minutes, @histogram).count <= renders.count
  end

  test "ranges come off the wire as atoms we already have" do
    assert Metrics.fetch_range("days") == {:ok, :days}
    assert Metrics.fetch_range("eons") == :error
    assert Enum.map(Metrics.ranges(), &elem(&1, 0)) == [:minutes, :hours, :days, :months]
    assert Metrics.default_range() in Enum.map(Metrics.ranges(), &elem(&1, 0))
  end

  test "save/0 writes the history under the data directory" do
    assert String.starts_with?(Metrics.persistence_dir(), HelloLiveView.data_dir())
    assert Metrics.save() == :ok
    assert File.exists?(Path.join(Metrics.persistence_dir(), "history"))
  end
end
