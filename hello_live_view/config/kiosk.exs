import Config

# Loaded last, after target.exs, on the kiosk targets listed in mix.exs. Those
# targets build on kiosk_system_rpi4/rpi5, which add udev, the Weston
# compositor and the Cog browser to the regular Raspberry Pi systems. With this
# flag set, HelloLiveView.Application starts HelloLiveView.Kiosk, which runs
# that stack and points Cog at the Phoenix endpoint over loopback.
#
# Nothing else changes: the endpoint still listens on every interface, so the
# app is reachable over the network exactly as on the other targets.
config :hello_live_view, kiosk: true

# Myelin is a WPE WebKit extension that Cog loads. It injects small scripts
# into every page the kiosk shows; none of them run unless enabled here.
#
# trusted_origins lists the origins whose pages may tune the scripts with
# <meta name="myelin-..."> tags. The endpoint listens on port 80 on targets
# (config/runtime.exs), so as the browser sees it the app's origin has no port.
config :myelin,
  trusted_origins: ["http://localhost"],
  scripts: %{
    # A bouncing Nerves logo after this many idle seconds. Any touch or key
    # wakes the screen; the LiveView gets a "myelin:screensaver:hide" event.
    "screensaver" => %{enabled: true, idle: 300}
    # Also bundled: "keyboard" (a touch keyboard), "statusbar", "navbar",
    # "offline-banner", "debug-overlay" and "tap-to-top".
  }
