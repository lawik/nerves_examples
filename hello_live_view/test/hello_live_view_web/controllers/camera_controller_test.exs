defmodule HelloLiveViewWeb.CameraControllerTest do
  use HelloLiveViewWeb.ConnCase, async: false

  alias HelloLiveView.Camera
  alias HelloLiveView.CameraFixture

  setup do
    on_exit(fn -> Camera.stop() end)
    :ok
  end

  test "there is nothing to serve until a camera is watched", %{conn: conn} do
    assert conn |> get(~p"/camera/snapshot") |> response(404)
  end

  test "serves the latest still as a JPEG that must not be cached", %{conn: conn} do
    Camera.subscribe()
    :ok = Camera.watch("camera.test", "admin", "secret")
    assert_receive {:camera, %{taken_at: %DateTime{}}}

    conn = get(conn, ~p"/camera/snapshot?at=1")
    assert response(conn, 200) == CameraFixture.jpeg()
    assert response_content_type(conn, :jpeg) =~ "image/jpeg"
    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end
end
