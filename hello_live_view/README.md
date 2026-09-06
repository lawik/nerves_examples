# Nerves + LiveView Example

This example shows a Nerves Project with a Phoenix server embedded in the same
application.  In contrast to a [poncho
project](https://embedded-elixir.com/post/2017-05-19-poncho-projects/), there is
only one application supervision tree containing the Phoenix Endpoint and any
processes running on the device.

## Configuration

The order of configuration is loaded in a specific order:

* `config.exs`
* `host.exs` or `target.exs`  based on `MIX_TARGET`
* `prod.exs`, `dev.exs`, or `test.exs` based on `MIX_ENV`
* `runtime.exs` at runtime

To make configuration slightly more straightforward, the application is run with
`MIX_ENV=prod` when on the device.  Therefore, the configuration for Phoenix on
the target device is in the `prod.exs` config file.

## Developing

You can start the application just like any Phoenix project:

```bash
iex -S mix phx.server
```

## Flashing to a Device

You can burn the first image with the following commands:

```bash
# If you want to enable wifi:
# export NERVES_SSID="NetworkName" && export NERVES_PSK="password"
MIX_ENV=prod MIX_TARGET=host mix do deps.get, assets.deploy
MIX_ENV=prod MIX_TARGET=rpi3 mix do deps.get, firmware, burn
```

Once the image is running on the device, the following will build and update the
firmware over ssh.

```bash
# If you want to enable wifi:
# export NERVES_SSID="NetworkName" && export NERVES_PSK="password"
MIX_ENV=prod MIX_TARGET=host mix do deps.get, assets.deploy
MIX_ENV=prod MIX_TARGET=rpi3 mix do deps.get, firmware, upload your_app_name.local
```

## Network Configuration

The network and WiFi configuration are specified in the `target.exs` file.  In
order to specify the network name and password, they must be set as environment
variables `NERVES_SSID` `NERVES_PSK` at runtime.

If they are not specified, a warning will be printed when building firmware,
which either gives you a chance to stop the build and add the environment
variables or a clue as to why you are no longer able to access the device over
WiFi.

## Running as a Kiosk

The `kiosk_rpi4` and `kiosk_rpi5` targets build the same application on the
[kiosk systems](https://github.com/nerves-web-kiosk), which add udev, the Weston
compositor and the Cog browser to the regular Raspberry Pi systems. On boot
`HelloLiveView.Kiosk` starts that stack and points Cog at the Phoenix endpoint
over loopback, so an attached display shows the desktop. The endpoint still
listens on every interface, so the device is reachable over the network exactly
as on the other targets.

```bash
MIX_ENV=prod MIX_TARGET=host mix do deps.get, assets.deploy
MIX_ENV=prod MIX_TARGET=kiosk_rpi4 mix do deps.get, firmware, burn
```

[Myelin](https://hex.pm/packages/myelin) scripts run inside the browser on every
page it shows. The screensaver is enabled in `config/kiosk.exs`; the touch
keyboard and the other bundled scripts are switched on the same way.

To rotate the display or pick a mode, add a
`rootfs_overlay/etc/xdg/weston/weston.ini`:

```ini
[output]
name=HDMI-A-1
transform=rotate-270
```

## Making It Your Own

To use this project as a start for your own Nerves/LiveView project, first
replace the following strings throughout the project:

* `HelloLiveView` -> `YourAppName`
* `hello_live_view` -> `your_app_name`

```bash
# Might be necessary in MacOS to avoid a sed "illegal byte sequence" error
# export LC_CTYPE=C
# export LANG=C

find . -type f \( -iname "*.ex*" ! -path "./deps/*" ! -path "./_build/*" \) -print0 | xargs -0 sed -i '' -e 's/HelloLiveView/YourAppName/g'
find . -type f \( -iname "*.ex*" ! -path "./deps/*" ! -path "./_build/*" \) -print0 | xargs -0 sed -i '' -e 's/hello_live_view/your_app_name/g'
sed -i '' 's/hello_live_view/your_app_name/g' ./scripts/deploy.sh
```

Then rename the files and directories in lib:

```bash
mv lib/hello_live_view lib/your_app_name
mv lib/hello_live_view_web lib/your_app_name_web
mv lib/hello_live_view.ex lib/your_app_name.ex
mv liv/hello_live_view_web.ex lib/your_app_name_web.ex
```
