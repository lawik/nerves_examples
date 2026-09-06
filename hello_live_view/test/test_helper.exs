# The :camera tests need a real camera named in CAMERA_HOST, CAMERA_USER and
# CAMERA_PASSWORD; run them with `mix test --include camera`.
ExUnit.start(exclude: [:camera])
