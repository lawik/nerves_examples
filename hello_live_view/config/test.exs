import Config

# Keep test windowing state away from the dev layout in the shared temp dir.
config :hello_live_view, data_dir: Path.join(System.tmp_dir!(), "hello_live_view_test")

# No GPIO hardware on a build machine: use Circuits.GPIO's stub backend, 64
# simulated lines wired in pairs. macOS picks it by itself; Linux CI needs
# telling.
config :circuits_gpio, default_backend: {Circuits.GPIO.CDev, test: true}
config :circuits_i2c, default_backend: {Circuits.I2C.I2CDev, test: true}

# No camera on the network either; the fixture in test/support answers.
config :hello_live_view, camera_fetch: {HelloLiveView.CameraFixture, :snapshot}

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :hello_live_view, HelloLiveViewWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "skPYVgOS63ZmbyfKrcf4OwImk+OQiYt/I5fCzPvFzMIeg2vq1HYvNxAyIkntZVKk",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
