defmodule HelloLiveViewWeb.Components.Applications do
  @moduledoc """
  The Applications navigator and the body of an application's own window.

  Both are stateless. The LiveView polls `HelloLiveView.Applications` while a
  window is open and hands the result down; these components only lay it out.
  Every application shares one icon — nobody needs a bespoke face for
  `ring_logger`.
  """
  use Phoenix.Component

  import HelloLiveViewWeb.Components.Desktop, only: [haiku_icon: 1]
  import HelloLiveViewWeb.Format

  @doc "The window id for an application, as used by `HelloLiveView.Windows`."
  @spec window_id(atom() | String.t()) :: String.t()
  def window_id(name), do: "app-#{name}"

  @doc """
  The navigator: one row per loaded application. Clicking a row opens (or
  raises) that application's window.
  """
  attr :applications, :list, required: true, doc: "from HelloLiveView.Applications.list/0"
  attr :open, :list, required: true, doc: "ids of the open windows"
  attr :icon, :string, required: true, doc: "the icon every application shares"

  def app_list(assigns) do
    assigns =
      assign(assigns,
        started: Enum.count(assigns.applications, & &1.started?),
        total: length(assigns.applications)
      )

    ~H"""
    <div class="mb-2 flex flex-wrap items-baseline justify-between gap-x-3 text-[12px]">
      <span class="font-semibold">{@started} of {@total} loaded applications started</span>
      <span class="text-be-ink-soft">Select one to open it</span>
    </div>

    <ul class="be-doc be-list">
      <li :for={app <- @applications}>
        <button
          type="button"
          class="be-list__row"
          phx-click="open"
          phx-value-id={window_id(app.name)}
          aria-pressed={to_string(window_id(app.name) in @open)}
        >
          <.haiku_icon name={@icon} size={20} />
          <span class="min-w-0 flex-1">
            <span class="flex flex-wrap items-baseline gap-x-2">
              <span class="font-bold">{app.name}</span>
              <span class="be-mono text-be-ink-soft">{app.version}</span>
              <.status_tag started?={app.started?} />
            </span>
            <span class="block truncate text-be-ink-soft" title={app.description}>
              {app.description}
            </span>
          </span>
          <span class="be-mono shrink-0 tabular-nums text-be-ink-soft">
            {app.processes} proc
          </span>
        </button>
      </li>
    </ul>
    """
  end

  @doc """
  Everything about one application, with Start and Stop.

  `required` is the set of applications this desktop depends on: stopping one
  of those is allowed, but asks first. `info` is nil when the application is
  no longer loaded.
  """
  attr :name, :string, required: true
  attr :info, :map, default: nil, doc: "from HelloLiveView.Applications.info/1"
  attr :error, :string, default: nil, doc: "why the last Start or Stop failed"
  attr :required, :any, required: true, doc: "MapSet of application names"
  attr :icon, :string, required: true

  def app_details(%{info: nil} = assigns) do
    ~H"""
    <p class="p-4 text-center text-be-ink-soft">
      <span class="font-bold">{@name}</span> is not loaded on this node.
    </p>
    """
  end

  def app_details(assigns) do
    ~H"""
    <div class="flex items-start gap-3">
      <.haiku_icon name={@icon} size={40} />
      <div class="min-w-0 flex-1">
        <div class="flex flex-wrap items-baseline gap-x-2">
          <span class="text-[15px] font-bold">{@info.name}</span>
          <span class="be-mono text-be-ink-soft">{@info.version}</span>
        </div>
        <div :if={@info.description != ""} class="mt-0.5 text-be-ink-soft">
          {@info.description}
        </div>
        <div class="mt-2 flex flex-wrap gap-1.5">
          <.status_tag started?={@info.started?} />
          <span :if={@info.type} class="be-tag">{@info.type}</span>
          <span :if={@info.mod} class="be-tag be-mono normal-case">{inspect(@info.mod)}</span>
          <span :if={@info.mod == nil} class="be-tag be-tag--idle">library</span>
        </div>
      </div>
    </div>

    <div class="mt-3 flex flex-wrap items-center gap-2">
      <button
        type="button"
        class="be-btn"
        phx-click="app_start"
        phx-value-name={@info.name}
        disabled={@info.started?}
      >
        Start
      </button>
      <button
        type="button"
        class="be-btn"
        phx-click="app_stop"
        phx-value-name={@info.name}
        disabled={not @info.started? or @info.protected?}
        title={@info.protected? && "This desktop cannot run without it"}
        data-confirm={stop_confirmation(@info, @required)}
      >
        Stop
      </button>
      <span :if={@error} class="be-tag be-tag--warn normal-case">{@error}</span>
    </div>

    <hr class="be-divider" />

    <div class="grid grid-cols-3 gap-2">
      <.stat label="Processes" value={@info.processes} />
      <.stat label="Memory" value={format_bytes(@info.memory)} />
      <.stat label="Queued messages" value={@info.message_queue} />
      <.stat label="Reductions" value={format_count(@info.reductions)} />
      <.stat label="Modules" value={@info.modules} />
      <.stat label="Supervised children" value={length(@info.children)} />
    </div>

    <hr class="be-divider" />

    <dl class="be-field">
      <dt>Supervisor</dt>
      <dd class="be-mono">{@info.supervisor || "—"}</dd>
      <dt>Depends on</dt>
      <dd class="flex flex-wrap gap-x-2 gap-y-1">
        <span :if={@info.applications == []}>—</span>
        <button
          :for={dep <- @info.applications}
          type="button"
          class={["be-link", not dep.started? && "text-be-ink-soft"]}
          phx-click="open"
          phx-value-id={window_id(dep.name)}
          title={if dep.started?, do: "started", else: "not started"}
        >
          {dep.name}
        </button>
      </dd>
      <dt :if={@info.optional_applications != []}>Optional</dt>
      <dd :if={@info.optional_applications != []} class="be-mono">
        {Enum.join(@info.optional_applications, ", ")}
      </dd>
    </dl>

    <div :if={@info.children != []} class="be-doc mt-3">
      <div :for={child <- @info.children} class="be-row items-baseline">
        <span class="be-mono min-w-0 flex-1 truncate" title={child.id}>{child.id}</span>
        <span class="be-mono shrink-0 text-be-ink-soft">{child.label}</span>
        <span class={["be-tag shrink-0", if(child.alive?, do: "be-tag--ok", else: "be-tag--warn")]}>
          {child.type}
        </span>
      </div>
    </div>
    """
  end

  attr :started?, :boolean, required: true

  defp status_tag(assigns) do
    ~H"""
    <span class={["be-tag", if(@started?, do: "be-tag--ok", else: "be-tag--idle")]}>
      {if @started?, do: "started", else: "loaded"}
    </span>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp stat(assigns) do
    ~H"""
    <div class="be-stat">
      <span class="be-stat__value">{@value}</span>
      <span class="be-stat__label">{@label}</span>
    </div>
    """
  end

  defp stop_confirmation(%{name: name, protected?: false}, required) do
    if MapSet.member?(required, name) do
      "This desktop depends on #{name}. Stopping it may take the page down. Stop it anyway?"
    end
  end

  defp stop_confirmation(_info, _required), do: nil

  # 1536 -> "1.5 kB"
end
