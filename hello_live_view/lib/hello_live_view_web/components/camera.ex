defmodule HelloLiveViewWeb.Components.Camera do
  @moduledoc """
  The body of the Security Camera window: a form for the camera's address
  and login until one is watched, then its latest still and how it is going.

  Stateless. `HelloLiveView.Camera` does the watching and the LiveView hands
  its status down.
  """
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: HelloLiveViewWeb.Endpoint,
    router: HelloLiveViewWeb.Router,
    statics: HelloLiveViewWeb.static_paths()

  attr :camera, :map, default: nil, doc: "HelloLiveView.Camera.status(), nil while reading"
  attr :notice, :string, default: nil, doc: "why the last Start was refused"

  def camera_panel(%{camera: nil} = assigns) do
    ~H"""
    <p class="p-4 text-center text-be-ink-soft">Looking for the camera…</p>
    """
  end

  def camera_panel(%{camera: %{running?: false}} = assigns) do
    ~H"""
    <form class="be-doc p-3" phx-submit="camera_start">
      <p class="mb-3 text-be-ink-soft">
        A Milesight camera on the network. A still is fetched every five seconds
        and only the latest is kept. The address and login are remembered across
        reboots until Stop.
      </p>
      <dl class="be-field">
        <dt><label for="camera-host">Address</label></dt>
        <dd>
          <input
            id="camera-host"
            class="be-input w-full"
            type="text"
            name="host"
            placeholder="192.0.2.10"
            autocomplete="off"
            autocapitalize="off"
            spellcheck="false"
            required
          />
        </dd>
        <dt><label for="camera-user">User</label></dt>
        <dd>
          <input
            id="camera-user"
            class="be-input w-full"
            type="text"
            name="user"
            autocomplete="off"
            autocapitalize="off"
            spellcheck="false"
            required
          />
        </dd>
        <dt><label for="camera-password">Password</label></dt>
        <dd>
          <input
            id="camera-password"
            class="be-input w-full"
            type="password"
            name="password"
            autocomplete="off"
            required
          />
        </dd>
      </dl>
      <div class="mt-3 flex flex-wrap items-center gap-2">
        <button type="submit" class="be-btn be-btn--default">Start</button>
        <span :if={@notice} class="be-tag be-tag--warn normal-case">{@notice}</span>
        <span :if={@camera.error} class="be-tag be-tag--warn normal-case">{@camera.error}</span>
      </div>
    </form>
    """
  end

  def camera_panel(assigns) do
    ~H"""
    <div class="be-camera">
      <img
        :if={@camera.taken_at}
        src={~p"/camera/snapshot?at=#{DateTime.to_unix(@camera.taken_at, :millisecond)}"}
        alt={"Still from #{@camera.host}"}
      />
      <p :if={is_nil(@camera.taken_at)} class="be-camera__waiting">
        {if @camera.error, do: "No still yet.", else: "Waiting for the first still…"}
      </p>
    </div>

    <div class="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 text-[12px]">
      <span class="font-semibold">{@camera.host}</span>
      <span class="be-mono text-be-ink-soft">{@camera.user}</span>
      <span :if={@camera.taken_at} class="text-be-ink-soft">
        taken {Calendar.strftime(@camera.taken_at, "%H:%M:%S")} UTC, {div(@camera.bytes, 1024)} kB
      </span>
      <span :if={@camera.error} class="be-tag be-tag--warn normal-case">{@camera.error}</span>
      <span :if={@camera.fetching?} class="be-tag be-tag--idle">fetching</span>
      <button type="button" class="be-btn ml-auto" phx-click="camera_stop">Stop</button>
    </div>
    """
  end
end
