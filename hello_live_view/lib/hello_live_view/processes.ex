defmodule HelloLiveView.Processes do
  @moduledoc """
  A task-manager view of the BEAM process table.

  This is a loaded gun, deliberately. `force_quit/1` sends an untrappable
  `:kill`, so pointing it at a supervised process is the fastest way to watch a
  supervisor do its job — and pointing it at the wrong one will take the web UI
  down with it. That is the demo.

  Reading the table is cheap: `Process.info/2` on a few hundred processes costs
  microseconds each. Processes die between `Process.list/0` and `Process.info/2`
  all the time, so anything that vanishes mid-sweep is simply dropped.
  """

  # Columns the UI is allowed to sort by. Also the allow-list that keeps
  # String.to_atom/1 away from a value that arrives from the browser.
  @sortable [:name, :pid, :memory, :reductions, :message_queue_len, :status]

  @type row :: %{
          id: String.t(),
          pid: pid(),
          name: String.t(),
          memory: non_neg_integer(),
          reductions: non_neg_integer(),
          message_queue_len: non_neg_integer(),
          status: atom(),
          current: String.t()
        }

  @doc "Columns that `list/2` will sort by, in display order."
  @spec sortable_columns() :: [atom()]
  def sortable_columns, do: @sortable

  @doc """
  Resolve a column name that came from the browser, or `nil` if it is not one
  of ours. Never turns untrusted input into an atom.
  """
  @spec sort_column(String.t()) :: atom() | nil
  def sort_column(name) when is_binary(name),
    do: Enum.find(@sortable, &(Atom.to_string(&1) == name))

  def sort_column(_name), do: nil

  @doc "Every live process, described and sorted."
  @spec list(atom(), :asc | :desc) :: [row()]
  def list(sort_by \\ :memory, direction \\ :desc) do
    sort_by = if sort_by in @sortable, do: sort_by, else: :memory

    Process.list()
    |> Enum.map(&describe/1)
    |> Enum.reject(&is_nil/1)
    |> sort(sort_by, direction)
  end

  @doc """
  Ask a process to stop.

  `:shutdown` is trappable, so a process trapping exits gets a chance to clean
  up — and one that ignores it simply carries on, which is worth seeing.
  """
  @spec quit(String.t()) :: :ok | {:error, :unknown_pid | :not_alive}
  def quit(id), do: signal(id, :shutdown)

  @doc "Kill a process outright. `:kill` cannot be trapped or ignored."
  @spec force_quit(String.t()) :: :ok | {:error, :unknown_pid | :not_alive}
  def force_quit(id), do: signal(id, :kill)

  # ------------------------------------------------------------------ private

  defp signal(id, reason) do
    with {:ok, pid} <- to_pid(id),
         true <- Process.alive?(pid) do
      Process.exit(pid, reason)
      :ok
    else
      :error -> {:error, :unknown_pid}
      false -> {:error, :not_alive}
    end
  end

  defp describe(pid) do
    case Process.info(pid, [
           :registered_name,
           :memory,
           :reductions,
           :message_queue_len,
           :status,
           :current_function
         ]) do
      nil ->
        nil

      info ->
        %{
          id: id(pid),
          pid: pid,
          name: name(pid, info[:registered_name]),
          memory: info[:memory],
          reductions: info[:reductions],
          message_queue_len: info[:message_queue_len],
          status: info[:status],
          current: mfa(info[:current_function])
        }
    end
  end

  # A registered name if there is one, otherwise what the process was spawned
  # to run — which is what makes an anonymous pid identifiable.
  defp name(_pid, registered) when is_atom(registered), do: inspect(registered)
  defp name(pid, _unregistered), do: initial_call(pid)

  defp initial_call(pid) do
    pid |> :proc_lib.translate_initial_call() |> mfa()
  rescue
    _ -> "—"
  end

  defp mfa({module, function, arity}), do: "#{inspect(module)}.#{function}/#{arity}"
  defp mfa(_other), do: "—"

  @doc "The textual pid, `\"<0.123.0>\"`, used as the DOM id for a row."
  @spec id(pid()) :: String.t()
  def id(pid), do: pid |> :erlang.pid_to_list() |> List.to_string()

  defp to_pid(id) when is_binary(id) do
    {:ok, :erlang.list_to_pid(String.to_charlist(id))}
  rescue
    ArgumentError -> :error
  end

  defp to_pid(_id), do: :error

  # Sort text case-insensitively; everything else falls out of Erlang term order.
  defp sort(rows, :name, direction), do: Enum.sort_by(rows, &String.downcase(&1.name), direction)

  defp sort(rows, :status, direction),
    do: Enum.sort_by(rows, &Atom.to_string(&1.status), direction)

  defp sort(rows, column, direction), do: Enum.sort_by(rows, &Map.fetch!(&1, column), direction)
end
