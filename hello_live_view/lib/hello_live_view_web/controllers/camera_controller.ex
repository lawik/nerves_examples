defmodule HelloLiveViewWeb.CameraController do
  @moduledoc """
  Serves the latest still `HelloLiveView.Camera` holds.

  The window's `<img>` points here with the time the still was taken in the
  query string, so each new still is a new URL and the browser fetches it
  rather than showing the one it cached.
  """
  use HelloLiveViewWeb, :controller

  alias HelloLiveView.Camera

  def snapshot(conn, _params) do
    case Camera.latest() do
      {:ok, jpeg, _taken_at} ->
        conn
        |> put_resp_content_type("image/jpeg")
        |> put_resp_header("cache-control", "no-store")
        |> send_resp(200, jpeg)

      :error ->
        send_resp(conn, 404, "no snapshot yet")
    end
  end
end
