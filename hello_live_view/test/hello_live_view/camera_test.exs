defmodule HelloLiveView.CameraTest do
  use ExUnit.Case, async: false

  alias HelloLiveView.Camera
  alias HelloLiveView.CameraFixture

  # A private instance with its own settings file, so the device-wide one
  # and the other tests are left alone.
  setup do
    path =
      Path.join(
        System.tmp_dir!(),
        "hello_live_view_camera_test/#{System.unique_integer([:positive])}.config"
      )

    on_exit(fn -> File.rm(path) end)
    Camera.subscribe()
    {:ok, camera} = Camera.start_link(name: nil, path: path)
    %{camera: camera, path: path}
  end

  test "watch/3 fetches at once and keeps only the latest still", %{camera: camera} do
    assert Camera.latest(camera) == :error

    :ok = Camera.watch(camera, "camera.test", "admin", "secret")
    assert_receive {:camera, %{running?: true, taken_at: %DateTime{}, error: nil} = status}
    assert status.bytes == byte_size(CameraFixture.jpeg())
    assert {:ok, jpeg, %DateTime{}} = Camera.latest(camera)
    assert jpeg == CameraFixture.jpeg()

    refute Map.has_key?(status, :password)
  end

  test "a refused login is reported in words and no still is kept", %{camera: camera} do
    :ok = Camera.watch(camera, "camera.test", "admin", "wrong")
    assert_receive {:camera, %{running?: true, taken_at: nil, error: "the camera refused" <> _}}
    assert Camera.latest(camera) == :error

    :ok = Camera.watch(camera, "nowhere.test", "admin", "secret")
    assert_receive {:camera, %{error: "could not connect" <> _}}
  end

  test "the settings are saved, and a restarted process picks them up", %{
    camera: camera,
    path: path
  } do
    :ok = Camera.watch(camera, "camera.test", "admin", "secret")
    assert_receive {:camera, %{taken_at: %DateTime{}}}
    assert File.exists?(path)

    :ok = GenServer.stop(camera)
    {:ok, revived} = Camera.start_link(name: nil, path: path)
    assert_receive {:camera, %{running?: true, host: "camera.test", taken_at: %DateTime{}}}
    assert {:ok, _jpeg, _at} = Camera.latest(revived)
  end

  test "stop/0 drops the still and forgets the settings", %{camera: camera, path: path} do
    :ok = Camera.watch(camera, "camera.test", "admin", "secret")
    assert_receive {:camera, %{taken_at: %DateTime{}}}

    :ok = Camera.stop(camera)
    assert_receive {:camera, %{running?: false, taken_at: nil, error: nil}}
    assert Camera.latest(camera) == :error
    refute File.exists?(path)

    :ok = GenServer.stop(camera)
    {:ok, revived} = Camera.start_link(name: nil, path: path)
    assert %{running?: false} = Camera.status(revived)
  end

  test "settings that cannot be read are reported, not fatal", %{path: path} do
    File.write!(path, "not a term")
    {:ok, camera} = Camera.start_link(name: nil, path: path)

    assert %{running?: false, error: "the saved camera settings could not be decoded" <> _} =
             Camera.status(camera)

    # And watching again writes good ones over the bad.
    :ok = Camera.watch(camera, "camera.test", "admin", "secret")
    assert_receive {:camera, %{running?: true, error: nil}}
  end

  test "settings that cannot be saved still leave the camera watched", %{path: _path} do
    unwritable =
      Path.join(System.tmp_dir!(), "hello_live_view_camera_test/a_file_not_a_dir/x.config")

    File.mkdir_p!(Path.dirname(Path.dirname(unwritable)))
    File.write!(Path.dirname(unwritable), "in the way")
    on_exit(fn -> File.rm(Path.dirname(unwritable)) end)

    {:ok, camera} = Camera.start_link(name: nil, path: unwritable)
    :ok = Camera.watch(camera, "camera.test", "admin", "secret")
    assert_receive {:camera, %{running?: true, error: "the camera is watched, but" <> _}}
    assert_receive {:camera, %{taken_at: %DateTime{}}}
  end
end
