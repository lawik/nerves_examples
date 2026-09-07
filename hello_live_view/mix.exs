defmodule HelloLiveView.MixProject do
  use Mix.Project

  @app :hello_live_view
  @version "0.1.0"

  @nerves_targets [
    :rpi,
    :rpi0,
    :rpi2,
    :rpi3,
    :rpi3a,
    :rpi4,
    :rpi5,
    :bbb,
    :x86_64,
    :trellis,
    :mangopi_mq_pro,
    # The emulated board, for running the firmware without hardware.
    :qemu_aarch64,
    # Seeed reComputer R22xx (CM5): a fork of nerves_system_rpi5 with the
    # board's device tree overlay and drivers, plus the recomputer_r22 library
    # for its buzzer, RGB LED and UPS. See ADDING_THE_TARGET.md in
    # https://github.com/lawik/recomputer_r22.
    :recomputer_r22
  ]

  # The kiosk systems are nerves_system_rpi4/rpi5 plus udev, the Weston
  # compositor and the Cog browser, so the device can show this app on its own
  # display. See config/kiosk.exs and HelloLiveView.Kiosk.
  @kiosk_targets [:kiosk_rpi4, :kiosk_rpi5]

  @all_targets @nerves_targets ++ @kiosk_targets

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      archives: [nerves_bootstrap: "~> 1.13"],
      compilers: Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      releases: [{@app, release()}]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {HelloLiveView.Application, []},
      # :inets and :ssl are for HelloLiveView.Milesight's HTTP client.
      extra_applications: [:logger, :runtime_tools, :os_mon, :inets, :ssl]
    ]
  end

  def cli do
    [preferred_targets: [run: :host, test: :host]]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      # Initial pheonix deps
      {:phoenix, "~> 1.8.3"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.6", only: :dev, targets: :host},
      {:phoenix_live_view, "~> 1.0"},
      {:floki, ">= 0.30.0", only: :test},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8"},
      {:esbuild, "~> 0.7", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.5.1", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      # Local metrics history for the Mobius window (HelloLiveView.Metrics):
      # scrapes the telemetry metrics into ring buffers under /data, so a
      # device carries its own recent history across reboots. Pinned to main
      # for the DDSketch histograms, which are newer than the Hex release.
      {:mobius, github: "mobius-home/mobius", ref: "fdf8667"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:plug_cowboy, "~> 2.5"},

      # Dependencies for all targets
      {:nerves, "~> 1.12", runtime: false},
      {:shoehorn, "~> 0.9.1"},
      {:ring_logger, "~> 0.11.0"},
      {:toolshed, "~> 0.5"},
      # GPIO lines for the desktop's GPIO window. On the host it runs a stub
      # backend with 64 simulated lines wired in pairs, so the window works
      # without hardware.
      {:circuits_gpio, "~> 2.3"},
      # I2C buses for the desktop's I2C window. On the host it builds a test
      # backend with three fake buses, one device answering on each.
      {:circuits_i2c, "~> 2.1"},

      # Dependencies for all targets except :host
      {:nerves_runtime, "~> 0.13.0", targets: @all_targets},
      {:nerves_pack, "~> 0.7.0", targets: @all_targets},

      # Dependencies for specific targets
      # NOTE: It's generally low risk and recommended to follow minor version
      # bumps to Nerves systems. Since these include Linux kernel and Erlang
      # version updates, please review their release notes in case
      # changes to your application are needed.
      {:nerves_system_rpi, "~> 2.0", runtime: false, targets: :rpi},
      {:nerves_system_rpi0, "~> 2.0", runtime: false, targets: :rpi0},
      {:nerves_system_rpi2, "~> 2.0", runtime: false, targets: :rpi2},
      {:nerves_system_rpi3, "~> 2.0", runtime: false, targets: :rpi3},
      {:nerves_system_rpi3a, "~> 2.0", runtime: false, targets: :rpi3a},
      {:nerves_system_rpi4, "~> 2.0", runtime: false, targets: :rpi4},
      rpi5_system(Mix.target()),
      {:nerves_system_bbb, "~> 2.14", runtime: false, targets: :bbb},
      {:nerves_system_x86_64, "~> 1.19", runtime: false, targets: :x86_64},
      {:nerves_system_trellis, "~> 0.4", runtime: false, targets: :trellis},
      {:nerves_system_mangopi_mq_pro, "~> 0.4", runtime: false, targets: :mangopi_mq_pro},
      {:nerves_system_qemu_aarch64, "~> 0.4", runtime: false, targets: :qemu_aarch64},
      # Fork of kiosk_system_rpi4 2.1.2 with CONFIG_BACKLIGHT_PWM=m, which the
      # Raspberry Pi Touch Display 2 needs. Upstream raspberrypi/linux d493058
      # split the backlight out of rpi-panel-v2-regulator into a generic
      # pwm-backlight node, and the stock defconfig never enabled that driver:
      # the panel probe defers forever, vc4-drm never registers a DRM device and
      # Weston dies with "failed to create compositor backend".
      #
      # A prebuilt artifact is attached to the release, so this does not build
      # from source. The checksum in the asset name is derived from the system
      # source, so a new commit on that branch needs a rebuilt artifact.
      # Revert to {:kiosk_system_rpi4, "~> 2.1"} once the fix lands upstream.
      {:kiosk_system_rpi4,
       github: "lawik/kiosk_system_rpi4",
       tag: "v2.1.3-pwm-backlight.1",
       runtime: false,
       targets: :kiosk_rpi4},
      {:kiosk_system_rpi5, "~> 2.1", runtime: false, targets: :kiosk_rpi5},
      {:recomputer_r22, github: "lawik/recomputer_r22", targets: :recomputer_r22},

      # The kiosk's display stack. MuonTrap runs its OS processes; it is
      # already on every target through nerves_time, and is listed here for
      # the :wait_for option (1.8). Myelin is the WPE WebKit extension Cog
      # loads, and only cross-compiles against a kiosk system.
      {:muontrap, "~> 1.8", targets: @all_targets},
      {:myelin, "~> 0.1.1", targets: @kiosk_targets}
    ]
  end

  # nerves_system_rpi5 backs two targets: the Raspberry Pi 5 itself from Hex,
  # and the reComputer R22xx from a fork carrying that board's device tree
  # overlay and drivers. Mix allows one dependency per name, so the target
  # decides which one is declared. Note that `mix deps.get` rewrites the
  # nerves_system_rpi5 entry in mix.lock when switching between the two.
  defp rpi5_system(:recomputer_r22) do
    # The ref pins the commit the prebuilt system on the fork's v2.1.2 release
    # was built from, so everyone fetches the same artifact.
    {:nerves_system_rpi5,
     github: "lawik/nerves_system_rpi5", ref: "41e95be", runtime: false, targets: :recomputer_r22}
  end

  defp rpi5_system(_target), do: {:nerves_system_rpi5, "~> 2.0", runtime: false, targets: :rpi5}

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind default", "esbuild default"],
      "assets.deploy": ["tailwind default --minify", "esbuild default --minify", "phx.digest"]
    ]
  end

  def release do
    [
      overwrite: true,
      # Erlang distribution is not started automatically.
      # See https://hexdocs.pm/nerves_pack/readme.html#erlang-distribution
      cookie: "#{@app}_cookie",
      include_erts: &Nerves.Release.erts/0,
      steps: [&Nerves.Release.init/1, :assemble],
      strip_beams: Mix.env() == :prod or [keep: ["Docs"]]
    ]
  end
end
