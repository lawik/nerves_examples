defmodule HelloLiveView.WiFiTest do
  use ExUnit.Case, async: true

  alias HelloLiveView.WiFi

  # What vintage_net_wifi hands over is a struct, which the map access
  # syntax refuses; a fake with the same fields keeps that honest here.
  defmodule AccessPoint do
    defstruct [:bssid, :frequency, :band, :channel, :signal_dbm, :signal_percent, :flags, :ssid]
  end

  defp ap(ssid, signal, flags, extra \\ %{}) do
    Map.merge(
      %{
        ssid: ssid,
        bssid: "aa:bb:cc:dd:ee:#{signal}",
        signal_percent: signal,
        signal_dbm: -signal,
        band: :wifi_2_4_ghz,
        channel: 6,
        flags: flags
      },
      extra
    )
  end

  test "summarize/1 and describe/1 take the structs a scan produces" do
    scanned = %AccessPoint{
      bssid: "94:83:c4:76:cc:f0",
      frequency: 2412,
      band: :wifi_2_4_ghz,
      channel: 1,
      signal_dbm: -28,
      signal_percent: 97,
      flags: [:wpa2_psk_ccmp, :wpa2, :psk, :ccmp, :ess, :utf8],
      ssid: "home"
    }

    assert [%{ssid: "home", signal: 97, dbm: -28, security: "WPA2", joinable?: true}] =
             WiFi.summarize([scanned])
  end

  test "there is nothing to configure on the host" do
    refute WiFi.available?()
  end

  test "summarize/1 keeps the strongest of each SSID, drops hidden ones, strongest first" do
    networks =
      WiFi.summarize([
        ap("home", 40, [:wpa2, :psk, :ccmp, :ess]),
        ap("home", 70, [:wpa2, :psk, :ccmp, :ess]),
        ap("", 90, [:ess]),
        ap("cafe", 55, [:ess])
      ])

    assert Enum.map(networks, &{&1.ssid, &1.signal}) == [{"home", 70}, {"cafe", 55}]
  end

  test "summarize/1 also takes the map older vintage_net_wifi kept" do
    assert [%{ssid: "one"}] = WiFi.summarize(%{"aa" => ap("one", 10, [:ess])})
  end

  test "describe/1 reads security from new and old flags" do
    assert %{security: "WPA2", passphrase?: true, joinable?: true} =
             WiFi.describe(ap("a", 1, [:wpa2, :psk, :ccmp, :ess]))

    assert %{security: "WPA2", passphrase?: true} =
             WiFi.describe(ap("b", 1, [:wpa2_psk_ccmp, :ess]))

    assert %{security: "WPA3", passphrase?: true} =
             WiFi.describe(ap("c", 1, [:wpa2, :sae, :ccmp]))

    assert %{security: "WPA", passphrase?: true} = WiFi.describe(ap("d", 1, [:wpa_psk_ccmp_tkip]))

    assert %{security: "open", passphrase?: false, joinable?: true} =
             WiFi.describe(ap("e", 1, [:ess]))

    assert %{security: "WPA2", passphrase?: false, joinable?: false} =
             WiFi.describe(ap("corp", 1, [:wpa2_eap_ccmp, :ess]))
  end
end
