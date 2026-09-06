defmodule HelloLiveView.CameraFixture do
  @moduledoc """
  Stands in for a camera in tests (see `:camera_fetch` in `config/test.exs`).

  `camera.test` with the login `admin` / `secret` answers with the smallest
  JPEG there is; any other login is refused; any other host is unreachable.
  """

  # Start-of-image and end-of-image markers and nothing in between.
  @jpeg <<0xFF, 0xD8, 0xFF, 0xD9>>

  def jpeg, do: @jpeg

  def snapshot("camera.test", "admin", "secret"), do: {:ok, @jpeg}
  def snapshot("camera.test", _user, _password), do: {:error, :unauthorized}
  def snapshot(_host, _user, _password), do: {:error, {:failed_connect, []}}
end
