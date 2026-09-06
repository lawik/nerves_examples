defmodule HelloLiveView.ApplicationsTest do
  use ExUnit.Case, async: true

  alias HelloLiveView.Applications

  test "list/0 covers every loaded application with a process count" do
    list = Applications.list()
    names = Enum.map(list, & &1.name)

    assert :kernel in names
    assert names == Enum.sort(names)
    assert Enum.find(list, &(&1.name == :kernel)).processes > 0
    assert Enum.find(list, &(&1.name == :kernel)).started?
  end

  test "info/1 describes a running application" do
    info = Applications.info(:kernel)

    assert info.started?
    assert info.type == :permanent
    assert info.processes > 0
    assert info.memory > 0
    assert info.supervisor == ":kernel_sup"
    assert Enum.any?(info.children, &(&1.type == :supervisor))
    assert info.protected?
  end

  test "info/1 is nil for an application that is not loaded" do
    assert Applications.info(:definitely_not_an_application) == nil
  end

  test "stop/1 refuses the applications this desktop cannot live without" do
    assert Applications.stop(:kernel) == {:error, :protected}
    assert Applications.stop(:hello_live_view) == {:error, :protected}
  end

  test "required_by_ui/0 is the transitive dependency closure of this app" do
    required = Applications.required_by_ui()

    assert MapSet.member?(required, :hello_live_view)
    assert MapSet.member?(required, :phoenix_live_view)
    assert MapSet.member?(required, :kernel)
  end

  test "fetch_name/1 resolves loaded applications only" do
    assert Applications.fetch_name("kernel") == {:ok, :kernel}
    assert Applications.fetch_name("no_such_application_here") == :error
  end
end
