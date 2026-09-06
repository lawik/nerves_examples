defmodule HelloLiveView.ShellTest do
  use ExUnit.Case, async: false

  alias HelloLiveView.Shell

  setup do
    {:ok, shell} = Shell.start()
    on_exit(fn -> Shell.stop(shell) end)
    %{shell: shell}
  end

  # Output arrives in chunks; gather it until the expected text shows up.
  defp output_until(shell, pattern, acc \\ "") do
    receive do
      {:shell, ^shell, {:output, text}} ->
        acc = acc <> text
        if acc =~ pattern, do: acc, else: output_until(shell, pattern, acc)
    after
      5_000 -> flunk("no #{inspect(pattern)} in #{inspect(acc)}")
    end
  end

  defp prompt(shell) do
    receive do
      {:shell, ^shell, {:prompt, prompt}} -> prompt
    after
      5_000 -> flunk("IEx never asked for a line")
    end
  end

  test "is a real IEx session", %{shell: shell} do
    assert output_until(shell, "Interactive Elixir") =~ System.version()
    assert prompt(shell) == "iex(1)> "

    Shell.input(shell, "21 * 2")
    assert output_until(shell, "42")
    assert prompt(shell) == "iex(2)> "
  end

  test "keeps asking until the expression is complete", %{shell: shell} do
    prompt(shell)

    Shell.input(shell, "[1,")
    assert prompt(shell) == "...(1)> "

    Shell.input(shell, "2]")
    assert output_until(shell, "[1, 2]")
  end

  test "evaluates the .iex.exs, so Toolshed is there as over SSH", %{shell: shell} do
    prompt(shell)
    Shell.input(shell, ~s|cmd("echo toolshed-ok")|)
    assert output_until(shell, "toolshed-ok")
  end

  test "a line typed while IEx is busy waits its turn", %{shell: shell} do
    prompt(shell)
    Shell.input(shell, "Process.sleep(200)")
    Shell.input(shell, "\"after\"")
    assert output_until(shell, "after")
  end

  test "interrupt/1 stops whatever is running", %{shell: shell} do
    prompt(shell)
    Shell.input(shell, "Process.sleep(:infinity)")
    Shell.interrupt(shell)

    assert output_until(shell, "interrupted")
    assert prompt(shell) =~ "iex("
  end

  test "goes away with its owner" do
    test = self()

    owner =
      spawn(fn ->
        {:ok, shell} = Shell.start()
        send(test, {:started, shell})
        receive do: (:stop -> :ok)
      end)

    assert_receive {:started, shell}
    ref = Process.monitor(shell)
    send(owner, :stop)
    assert_receive {:DOWN, ^ref, :process, ^shell, _reason}, 1_000
  end
end
