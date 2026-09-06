defmodule HelloLiveViewWeb.Components.WiFi do
  @moduledoc """
  The body of the WiFi window: where the interface stands, the networks in
  range, and a way to join one.

  Stateless. The LiveView reads and subscribes through `HelloLiveView.WiFi`
  and hands the result down; this only lays it out.
  """
  use Phoenix.Component

  attr :wifi, :map, default: nil, doc: "the LiveView's :wifi assign, nil while reading"

  def wifi_panel(%{wifi: nil} = assigns) do
    ~H"""
    <p class="p-4 text-center text-be-ink-soft">Looking at the interface…</p>
    """
  end

  def wifi_panel(%{wifi: %{available?: false}} = assigns) do
    ~H"""
    <p class="p-4 text-center text-be-ink-soft">
      There is no WiFi to configure here. On a device this shows what
      <span class="be-mono">{@wifi.ifname}</span>
      can see and joins a network; VintageNet only runs on a target.
    </p>
    """
  end

  def wifi_panel(assigns) do
    ~H"""
    <dl class="be-field">
      <dt>Interface</dt>
      <dd class="be-mono">{@wifi.status.ifname}</dd>
      <dt>Connection</dt>
      <dd>
        <span class={["be-tag", connection_class(@wifi.status.connection)]}>
          {@wifi.status.connection}
        </span>
        <span class="be-mono ml-1 text-be-ink-soft">{@wifi.status.state}</span>
      </dd>
      <dt>Network</dt>
      <dd>
        <span :if={@wifi.status.ssid}>
          {@wifi.status.ssid}
          <span :if={@wifi.status.signal} class="be-mono ml-1 text-be-ink-soft">
            {@wifi.status.signal}%
          </span>
        </span>
        <span :if={is_nil(@wifi.status.ssid)} class="text-be-ink-soft">not associated</span>
      </dd>
      <dt>Addresses</dt>
      <dd class="be-mono break-all">
        {if @wifi.status.addresses == [], do: "—", else: Enum.join(@wifi.status.addresses, "  ")}
      </dd>
      <dt>Saved</dt>
      <dd>
        {if @wifi.status.configured == [],
          do: "nothing",
          else: Enum.join(@wifi.status.configured, ", ")}
      </dd>
    </dl>

    <p :if={@wifi.notice} class="mt-2">
      <span class="be-tag be-tag--warn normal-case">{@wifi.notice}</span>
    </p>

    <hr class="be-divider" />

    <form :if={@wifi.selected} class="be-doc mb-3 p-3" phx-submit="wifi_join">
      <input type="hidden" name="ssid" value={@wifi.selected.ssid} />
      <div class="mb-2 flex flex-wrap items-baseline gap-x-2">
        <span class="font-bold">Join {@wifi.selected.ssid}</span>
        <span class="be-tag">{@wifi.selected.security}</span>
      </div>
      <p :if={not @wifi.selected.joinable?} class="text-be-ink-soft">
        This network takes a login or a certificate, which this window cannot provide.
      </p>
      <div :if={@wifi.selected.joinable?} class="flex flex-wrap items-center gap-2">
        <input
          :if={@wifi.selected.passphrase?}
          class="be-input"
          type="password"
          name="psk"
          placeholder="Passphrase"
          autocomplete="off"
          aria-label="Passphrase"
        />
        <button type="submit" class="be-btn be-btn--default">Join</button>
        <button type="button" class="be-btn" phx-click="wifi_cancel">Cancel</button>
      </div>
      <button
        :if={not @wifi.selected.joinable?}
        type="button"
        class="be-btn"
        phx-click="wifi_cancel"
      >
        Cancel
      </button>
    </form>

    <div class="mb-2 flex flex-wrap items-baseline justify-between gap-x-3 text-[12px]">
      <span class="font-semibold">{count(length(@wifi.networks))} in range</span>
      <span class="text-be-ink-soft">
        {if @wifi.networks == [] and not @wifi.scanned?,
          do: "scanning…",
          else: "select one to join it"}
      </span>
    </div>

    <ul class="be-doc be-list">
      <li :for={network <- @wifi.networks}>
        <button
          type="button"
          class="be-list__row items-center"
          phx-click="wifi_select"
          phx-value-ssid={network.ssid}
          aria-pressed={to_string(@wifi.selected != nil and @wifi.selected.ssid == network.ssid)}
        >
          <span class="min-w-0 flex-1 truncate">
            <span class="font-bold">{network.ssid}</span>
            <span class="be-mono ml-2 text-be-ink-soft">{network.dbm} dBm</span>
          </span>
          <span class="be-meter w-16 shrink-0" title={"#{network.signal}%"}>
            <span class="be-meter__fill block" style={"width: #{network.signal}%"}></span>
          </span>
          <span class="be-tag shrink-0">{network.security}</span>
          <span :if={network.ssid == @wifi.status.ssid} class="be-tag be-tag--ok shrink-0">
            current
          </span>
          <span
            :if={network.ssid != @wifi.status.ssid and network.ssid in @wifi.status.configured}
            class="be-tag be-tag--idle shrink-0"
          >
            saved
          </span>
        </button>
      </li>
    </ul>
    """
  end

  defp connection_class(:internet), do: "be-tag--ok"
  defp connection_class(:lan), do: "be-tag--idle"
  defp connection_class(_disconnected), do: "be-tag--warn"

  defp count(1), do: "1 network"
  defp count(n), do: "#{n} networks"
end
