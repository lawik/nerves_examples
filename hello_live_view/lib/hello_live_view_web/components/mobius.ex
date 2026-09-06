defmodule HelloLiveViewWeb.Components.Mobius do
  @moduledoc """
  The body of the Mobius window: a card per metric, with its recent history
  drawn into it.

  Stateless. The LiveView polls `HelloLiveView.Metrics.history/1` while the
  window is open and hands the result down. The charts are inline SVG built
  here from the samples, so nothing runs in the browser: a gauge gets a line
  across the window's time span, a histogram gets its bins as bars.
  """
  use Phoenix.Component

  import HelloLiveViewWeb.Format

  # The plots are drawn into this box and stretched to the card, so the
  # numbers here are proportions, not pixels.
  @plot_width 100
  @plot_height 30
  @plot_pad 1.5
  @view_box "0 0 #{@plot_width} #{@plot_height}"

  @doc "The element id of a metric's card, for anyone who needs to find it."
  @spec card_id(String.t()) :: String.t()
  def card_id(name), do: "metric-" <> String.replace(name, ".", "-")

  attr :history, :map, default: nil, doc: "HelloLiveView.Metrics.history/1, nil until first read"
  attr :notice, :map, default: nil, doc: "%{text:, ok?:} about the last Save Now, if any"
  attr :dir, :string, required: true, doc: "where Mobius keeps the history on disk"

  def mobius_panel(%{history: nil} = assigns) do
    ~H"""
    <p class="p-4 text-center text-be-ink-soft">Reading the history…</p>
    """
  end

  def mobius_panel(assigns) do
    assigns =
      assign(assigns, :count, Enum.sum(for g <- assigns.history.groups, do: length(g.metrics)))

    ~H"""
    <div class="mb-2 flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1 text-[12px]">
      <span class="font-semibold">
        {@count} metrics over the last {String.downcase(@history.label)}
      </span>
      <span
        :if={@notice}
        class={["be-tag normal-case", if(@notice.ok?, do: "be-tag--ok", else: "be-tag--warn")]}
      >
        {@notice.text}
      </span>
      <span
        class="be-mono truncate text-be-ink-soft"
        title={"Sampled every second, written to #{@dir}"}
      >
        {@dir}
      </span>
    </div>

    <section :for={group <- @history.groups} class="mb-3 last:mb-0">
      <h3 class="be-heading">{group.title}</h3>
      <div class="be-charts">
        <%= for metric <- group.metrics do %>
          <.gauge_card
            :if={metric.kind == :gauge}
            metric={metric}
            from={@history.from}
            to={@history.to}
          />
          <.histogram_card :if={metric.kind == :histogram} metric={metric} />
        <% end %>
      </div>
    </section>
    """
  end

  # A gauge: the latest reading, the line it took to get there and its range.
  attr :metric, :map, required: true
  attr :from, :integer, required: true
  attr :to, :integer, required: true

  defp gauge_card(assigns) do
    ~H"""
    <div class="be-chart" id={card_id(@metric.name)}>
      <div class="be-chart__head">
        <span class="be-chart__label" title={@metric.name}>{@metric.label}</span>
        <span class="be-chart__value">{value(@metric.current, @metric.unit)}</span>
      </div>
      <.sparkline series={@metric.series} from={@from} to={@to} />
      <div class="be-chart__foot">
        <%= if @metric.series == [] do %>
          <span>{empty_note(@metric.unit)}</span>
        <% else %>
          <span>min {value(@metric.min, @metric.unit)}</span>
          <span>max {value(@metric.max, @metric.unit)}</span>
          <span>{length(@metric.series)} samples since {since(@metric.series, @to)}</span>
        <% end %>
      </div>
    </div>
    """
  end

  # A histogram: the typical case up top, the distribution, and the tail
  # underneath, with how much of it stayed inside the budget.
  attr :metric, :map, required: true

  defp histogram_card(assigns) do
    ~H"""
    <div class="be-chart" id={card_id(@metric.name)}>
      <div class="be-chart__head">
        <span class="be-chart__label" title={@metric.name}>{@metric.label}</span>
        <span class="be-chart__value" title="median">
          {value(@metric.quantiles[0.5], @metric.unit)}
        </span>
      </div>
      <.bars bins={@metric.bins} />
      <div class="be-chart__foot">
        <%= if @metric.count == 0 do %>
          <span>nothing observed in this range</span>
        <% else %>
          <span>P95 {value(@metric.quantiles[0.95], @metric.unit)}</span>
          <span>P99 {value(@metric.quantiles[0.99], @metric.unit)}</span>
          <span>slowest {value(@metric.slowest, @metric.unit)}</span>
          <span class={@metric.within_budget < 90 && "font-semibold"}>
            {@metric.within_budget}% under {value(@metric.budget, @metric.unit)}
          </span>
          <span>{@metric.count} observed</span>
        <% end %>
      </div>
    </div>
    """
  end

  # The samples as one line, placed by time so a gap where the device was
  # off stays a gap. The line starts at the first sample rather than at the
  # start of the range: a device up for five minutes fills its card rather
  # than showing a sliver at the right edge of two empty hours, and the
  # card's foot says since when. A lone sample is a dot, thanks to the
  # round line cap.
  attr :series, :list, required: true
  attr :from, :integer, required: true
  attr :to, :integer, required: true

  defp sparkline(assigns) do
    assigns = assign(assigns, :points, points(assigns.series, assigns.from, assigns.to))

    ~H"""
    <svg
      class="be-chart__plot"
      viewBox={view_box()}
      preserveAspectRatio="none"
      aria-hidden="true"
    >
      <polyline :if={@points != ""} points={@points} vector-effect="non-scaling-stroke" />
    </svg>
    """
  end

  # The bins as bars, tallest first to the peak. DDSketch bins are spaced
  # geometrically, so the x axis is an ordering, not a scale: each bar is
  # one bin, left to right from the quickest to the slowest.
  attr :bins, :list, required: true

  defp bars(assigns) do
    assigns = assign(assigns, :rects, rects(assigns.bins))

    ~H"""
    <svg
      class="be-chart__plot"
      viewBox={view_box()}
      preserveAspectRatio="none"
      aria-hidden="true"
    >
      <rect
        :for={{x, y, width, height} <- @rects}
        x={x}
        y={y}
        width={width}
        height={height}
      />
    </svg>
    """
  end

  @doc false
  # The `points` attribute of the sparkline's polyline, or "" without samples.
  @spec points([{integer(), number()}], integer(), integer()) :: String.t()
  def points([], _from, _to), do: ""

  def points(series, from, to) do
    values = Enum.map(series, &elem(&1, 1))
    {low, high} = Enum.min_max(values)
    {first, _value} = hd(series)
    start = clamp(first, from, to)
    span = max(to - start, 1)
    usable = @plot_height - 2 * @plot_pad

    Enum.map_join(series, " ", fn {ts, value} ->
      x = (clamp(ts, from, to) - start) / span * @plot_width

      y =
        if high == low,
          do: @plot_height / 2,
          else: @plot_height - @plot_pad - (value - low) / (high - low) * usable

      "#{coordinate(x)},#{coordinate(y)}"
    end)
  end

  @doc false
  # One `{x, y, width, height}` per bin, in bin order, standing on the
  # bottom edge and scaled to the tallest.
  @spec rects([{number(), pos_integer()}]) :: [
          {String.t(), String.t(), String.t(), String.t()}
        ]
  def rects([]), do: []

  def rects(bins) do
    peak = bins |> Enum.map(&elem(&1, 1)) |> Enum.max()
    slot = @plot_width / length(bins)
    gap = min(slot / 4, 0.6)

    bins
    |> Enum.with_index()
    |> Enum.map(fn {{_value, count}, index} ->
      height = count / peak * (@plot_height - @plot_pad)

      {coordinate(index * slot + gap / 2), coordinate(@plot_height - height),
       coordinate(slot - gap), coordinate(height)}
    end)
  end

  defp view_box, do: @view_box

  defp clamp(ts, from, to), do: ts |> max(from) |> min(to)

  # When the first sample was taken, on the device's clock: the time of day
  # if that was today, the date as well if not.
  defp since([{first, _value} | _rest], to) do
    local = first |> :calendar.system_time_to_local_time(:second) |> NaiveDateTime.from_erl!()
    Calendar.strftime(local, if(to - first < 24 * 60 * 60, do: "%H:%M", else: "%d %b %H:%M"))
  end

  defp coordinate(number), do: :erlang.float_to_binary(number * 1.0, decimals: 1)

  @doc """
  A reading in its unit, for reading at a glance.

      iex> HelloLiveViewWeb.Components.Mobius.value(37, :percent)
      "37%"
      iex> HelloLiveViewWeb.Components.Mobius.value(0.4321, :milliseconds)
      "432 µs"
      iex> HelloLiveViewWeb.Components.Mobius.value(nil, :bytes)
      "—"
  """
  @spec value(number() | nil, HelloLiveView.Metrics.unit()) :: String.t()
  def value(nil, _unit), do: "—"
  def value(number, :percent), do: "#{round(number)}%"
  def value(number, :bytes), do: format_bytes(round(number))
  def value(number, :count), do: format_count(round(number))
  def value(number, :load), do: :erlang.float_to_binary(number * 1.0, decimals: 2)
  def value(number, :celsius), do: "#{:erlang.float_to_binary(number * 1.0, decimals: 1)} °C"
  def value(ms, :milliseconds) when ms < 1, do: "#{round(ms * 1000)} µs"

  def value(ms, :milliseconds) when ms < 10,
    do: "#{:erlang.float_to_binary(ms * 1.0, decimals: 1)} ms"

  def value(ms, :milliseconds) when ms < 1000, do: "#{round(ms)} ms"
  def value(ms, :milliseconds), do: "#{:erlang.float_to_binary(ms / 1000, decimals: 1)} s"

  # A gauge with no samples either has nothing to measure here or has not
  # been measured yet; the unit says which is likelier.
  defp empty_note(:celsius), do: "no thermal zone on this platform"
  defp empty_note(_unit), do: "no samples in this range"
end
