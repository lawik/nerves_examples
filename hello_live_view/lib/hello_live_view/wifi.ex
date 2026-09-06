defmodule HelloLiveView.WiFi do
  @moduledoc """
  The device's WiFi, in a shape the desktop can show and change.

  VintageNet owns the interface. Its state is a property table this module
  reads for `status/0` and subscribes the window to, so a change (an
  association, an address, a finished scan) arrives as a message rather than
  on a timer. A scan is asked for with `scan/0`; the results land on the
  access points property a moment later and `summarize/1` turns them into
  one entry per network, strongest first.

  Joining goes through `VintageNetWiFi.quick_configure/2`, the same call the
  Nerves docs have people type at the IEx prompt. It writes a configuration
  for `wlan0` that VintageNet persists to `/data`, so the network is back
  after a reboot and outlives the one baked into the firmware. `forget/0`
  writes an empty one.

  VintageNet only exists on a device. On the host `available?/0` is false and
  the window says so.
  """

  @ifname "wlan0"

  # Both are target-only deps; keep the host build warning-free.
  @compile {:no_warn_undefined, [VintageNet, VintageNetWiFi]}

  # Everything the window shows, for `subscribe/0`.
  @watched [
    ["connection"],
    ["state"],
    ["addresses"],
    ["config"],
    ["wifi", "current_ap"],
    ["wifi", "access_points"]
  ]

  @type network :: %{
          ssid: String.t(),
          bssid: String.t() | nil,
          signal: 0..100,
          dbm: integer() | nil,
          band: atom() | nil,
          channel: non_neg_integer() | nil,
          security: String.t(),
          joinable?: boolean(),
          passphrase?: boolean()
        }

  @type status :: %{
          ifname: String.t(),
          present?: boolean(),
          connection: :disconnected | :lan | :internet,
          state: atom(),
          ssid: String.t() | nil,
          signal: 0..100 | nil,
          addresses: [String.t()],
          configured: [String.t()]
        }

  @doc "The interface this configures."
  @spec ifname() :: String.t()
  def ifname, do: @ifname

  @doc "Whether there is a WiFi interface to configure: a device with the adapter present."
  @spec available?() :: boolean()
  def available? do
    Code.ensure_loaded?(VintageNetWiFi) and property(["present"]) == true
  end

  @doc "Where the interface stands right now."
  @spec status() :: status()
  def status do
    current = property(["wifi", "current_ap"])

    %{
      ifname: @ifname,
      present?: property(["present"]) == true,
      connection: property(["connection"]) || :disconnected,
      state: property(["state"]) || :unknown,
      ssid: current && current.ssid,
      signal: current && current.signal_percent,
      addresses: for(%{address: address} <- property(["addresses"]) || [], do: format(address)),
      configured: configured_ssids(property(["config"]))
    }
  end

  @doc "The networks the last scan found."
  @spec networks() :: [network()]
  def networks, do: summarize(property(["wifi", "access_points"]) || [])

  @doc "Ask for a scan. The results arrive on the access points property."
  @spec scan() :: :ok | {:error, term()}
  def scan do
    case VintageNet.scan(@ifname) do
      {:error, _reason} = error -> error
      _ok -> :ok
    end
  end

  @doc "Join a network. No passphrase means an open one."
  @spec join(String.t(), String.t() | nil) :: :ok | {:error, term()}
  def join(ssid, passphrase) when passphrase in [nil, ""],
    do: VintageNetWiFi.quick_configure(ssid)

  def join(ssid, passphrase), do: VintageNetWiFi.quick_configure(ssid, passphrase)

  @doc "Drop every configured network. The interface stays up, associated with nothing."
  @spec forget() :: :ok | {:error, term()}
  def forget, do: VintageNet.configure(@ifname, %{type: VintageNetWiFi})

  @doc "Have `{VintageNet, property, old, new, meta}` sent here for everything the window shows."
  @spec subscribe() :: :ok
  def subscribe, do: Enum.each(@watched, &VintageNet.subscribe(["interface", @ifname | &1]))

  @spec unsubscribe() :: :ok
  def unsubscribe, do: Enum.each(@watched, &VintageNet.unsubscribe(["interface", @ifname | &1]))

  @doc """
  One entry per SSID, the strongest of its access points, hidden networks
  dropped, strongest first.

  Takes what the access points property holds, which older vintage_net_wifi
  kept as a map by BSSID and newer ones as a list.
  """
  @spec summarize(map() | [map()]) :: [network()]
  def summarize(access_points) when is_map(access_points),
    do: summarize(Map.values(access_points))

  def summarize(access_points) do
    access_points
    |> Enum.reject(&(&1.ssid in ["", nil]))
    |> Enum.group_by(& &1.ssid)
    |> Enum.map(fn {_ssid, aps} ->
      aps |> Enum.max_by(&(&1.signal_percent || 0)) |> describe()
    end)
    |> Enum.sort_by(&{-&1.signal, &1.ssid})
  end

  @doc """
  An access point as the window shows it.

  The flags say how a network is secured. Newer vintage_net_wifi lists them
  one by one (`:wpa2`, `:psk`, `:sae`); older ones as combined atoms such as
  `:wpa2_psk_ccmp`. Both are read by name, so either works. A network that
  only takes enterprise logins is shown but cannot be joined from here.
  """
  @spec describe(map()) :: network()
  def describe(access_point) do
    # An AccessPoint is a struct, so no `access_point[:flags]` here.
    flags = access_point |> Map.get(:flags) |> List.wrap() |> Enum.map(&Atom.to_string/1)
    security = security(flags)
    passphrase? = flagged?(flags, "psk") or flagged?(flags, "sae")

    %{
      ssid: access_point.ssid,
      bssid: Map.get(access_point, :bssid),
      signal: Map.get(access_point, :signal_percent) || 0,
      dbm: Map.get(access_point, :signal_dbm),
      band: Map.get(access_point, :band),
      channel: Map.get(access_point, :channel),
      security: security,
      passphrase?: passphrase?,
      joinable?: security == "open" or passphrase?
    }
  end

  defp security(flags) do
    cond do
      flagged?(flags, "sae") or flagged?(flags, "wpa3") -> "WPA3"
      flagged?(flags, "wpa2") -> "WPA2"
      flagged?(flags, "wpa") -> "WPA"
      flagged?(flags, "wep") -> "WEP"
      true -> "open"
    end
  end

  defp flagged?(flags, word), do: Enum.any?(flags, &String.contains?(&1, word))

  defp property(path), do: VintageNet.get(["interface", @ifname | path])

  defp configured_ssids(%{vintage_net_wifi: %{networks: networks}}) do
    for %{ssid: ssid} <- networks, is_binary(ssid), do: ssid
  end

  defp configured_ssids(_config), do: []

  defp format(address) when is_tuple(address), do: to_string(:inet.ntoa(address))
  defp format(address), do: inspect(address)
end
