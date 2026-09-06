defmodule HelloLiveView do
  @moduledoc """
  HelloLiveView keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  @doc """
  Where this app keeps what has to survive a reboot: `/data`, the writable
  partition on a Nerves device. On the host, where `/data` does not exist, a
  directory under `System.tmp_dir!/0` stands in so `mix phx.server` behaves
  the same way. `config :hello_live_view, :data_dir` overrides both, which is
  how the tests keep their state away from the dev layout.

  The window layout (`HelloLiveView.Windows`) and the metrics history
  (`HelloLiveView.Metrics`) both live here.
  """
  @spec data_dir() :: String.t()
  def data_dir do
    Application.get_env(:hello_live_view, :data_dir) ||
      if File.dir?("/data"),
        do: "/data",
        else: Path.join(System.tmp_dir!(), "hello_live_view")
  end
end
