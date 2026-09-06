defmodule HelloLiveView.Applications do
  @moduledoc """
  What the application controller knows about every OTP application, in a
  shape the desktop can show.

  Process ownership is worked out the way Observer does it: every process
  spawned under an application's supervision tree inherits that application's
  master as its group leader. So one pass over `Process.list/0`, bucketed by
  group leader, gives per-application process counts and memory without
  walking a single supervision tree. Library applications (no callback
  module) have no master and therefore own no processes.
  """

  @app :hello_live_view

  # Stopping any of these takes this desktop down with no way to say so.
  # Everything else is fair game, with a warning for the rest of our deps.
  @untouchable [:kernel, :stdlib, :elixir, @app]

  # `which_children` on a wedged supervisor must not wedge the LiveView too.
  @call_timeout 500

  @type name :: atom()

  @type summary :: %{
          name: name(),
          description: String.t(),
          version: String.t(),
          started?: boolean(),
          type: :permanent | :transient | :temporary | nil,
          processes: non_neg_integer()
        }

  @doc "Every loaded application, sorted by name, with its process count."
  @spec list() :: [summary()]
  def list do
    info = :application.info()
    counts = process_counts(masters(info[:running]))
    started = info[:started]

    Application.loaded_applications()
    |> Enum.map(fn {name, description, version} ->
      %{
        name: name,
        description: to_string(description),
        version: to_string(version),
        started?: Keyword.has_key?(started, name),
        type: started[name],
        processes: Map.get(counts, name, 0)
      }
    end)
    |> Enum.sort_by(& &1.name)
  end

  @doc "Everything worth showing about one application, or nil if it is not loaded."
  @spec info(name()) :: map() | nil
  def info(name) do
    case Application.spec(name) do
      nil -> nil
      spec -> build_info(name, spec)
    end
  end

  @doc "Start an application and everything it depends on."
  @spec start(name()) :: :ok | {:error, term()}
  def start(name) do
    case Application.ensure_all_started(name) do
      {:ok, _started} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Stop an application, unless it is one this desktop cannot live without."
  @spec stop(name()) :: :ok | {:error, term()}
  def stop(name) do
    if protected?(name), do: {:error, :protected}, else: Application.stop(name)
  end

  @doc "Applications the desktop refuses to stop."
  @spec protected?(name()) :: boolean()
  def protected?(name), do: name in @untouchable

  @doc """
  This application and everything it transitively depends on: stopping any of
  them probably takes the page down, so the UI asks first.
  """
  @spec required_by_ui() :: MapSet.t(name())
  def required_by_ui, do: closure([@app], MapSet.new())

  @doc """
  Resolve a name from the wire to a loaded application's atom, without
  creating atoms from user input.
  """
  @spec fetch_name(String.t()) :: {:ok, name()} | :error
  def fetch_name(string) when is_binary(string) do
    Enum.find_value(Application.loaded_applications(), :error, fn {name, _desc, _vsn} ->
      if Atom.to_string(name) == string, do: {:ok, name}
    end)
  end

  # ---------------------------------------------------------------- details

  defp build_info(name, spec) do
    info = :application.info()
    started = info[:started]
    master = master_pid(info[:running][name])
    pids = owned_by(master)
    stats = process_stats(pids)
    {supervisor, children} = supervision(master)

    %{
      name: name,
      description: to_string(spec[:description] || ""),
      version: to_string(spec[:vsn] || ""),
      started?: Keyword.has_key?(started, name),
      type: started[name],
      mod: callback_module(spec[:mod]),
      protected?: protected?(name),
      supervisor: supervisor,
      children: children,
      processes: length(pids),
      memory: stats.memory,
      message_queue: stats.message_queue,
      reductions: stats.reductions,
      modules: length(spec[:modules] || []),
      applications:
        for(
          dep <- spec[:applications] || [],
          do: %{name: dep, started?: Keyword.has_key?(started, dep)}
        ),
      optional_applications: spec[:optional_applications] || []
    }
  end

  defp callback_module({mod, _args}), do: mod
  defp callback_module(_none), do: nil

  # `:application.info()[:running]` lists a master pid per started application,
  # or :undefined for library applications.
  defp master_pid(pid) when is_pid(pid), do: pid
  defp master_pid(_undefined), do: nil

  defp masters(running) do
    for {name, pid} <- running, is_pid(pid), into: %{}, do: {pid, name}
  end

  defp process_counts(masters) do
    Enum.reduce(Process.list(), %{}, fn pid, counts ->
      case Map.fetch(masters, group_leader(pid)) do
        {:ok, name} -> Map.update(counts, name, 1, &(&1 + 1))
        :error -> counts
      end
    end)
  end

  defp owned_by(nil), do: []
  defp owned_by(master), do: for(pid <- Process.list(), group_leader(pid) == master, do: pid)

  defp group_leader(pid) do
    case Process.info(pid, :group_leader) do
      {:group_leader, leader} -> leader
      nil -> nil
    end
  end

  defp process_stats(pids) do
    Enum.reduce(pids, %{memory: 0, message_queue: 0, reductions: 0}, fn pid, acc ->
      case Process.info(pid, [:memory, :message_queue_len, :reductions]) do
        nil ->
          acc

        stats ->
          %{
            memory: acc.memory + stats[:memory],
            message_queue: acc.message_queue + stats[:message_queue_len],
            reductions: acc.reductions + stats[:reductions]
          }
      end
    end)
  end

  # The application master's child is whatever `start/2` returned; normally
  # the top supervisor, whose children are the interesting part.
  defp supervision(nil), do: {nil, []}

  defp supervision(master) do
    case :application_master.get_child(master) do
      {pid, _mod} when is_pid(pid) -> {label(pid), children_of(pid)}
      _other -> {nil, []}
    end
  catch
    :exit, _reason -> {nil, []}
  end

  defp children_of(pid) do
    if supervisor?(pid) do
      pid
      |> GenServer.call(:which_children, @call_timeout)
      |> Enum.map(fn {id, child, type, _modules} ->
        %{
          id: inspect(id),
          type: type,
          alive?: is_pid(child),
          label: if(is_pid(child), do: label(child), else: inspect(child))
        }
      end)
    else
      []
    end
  catch
    :exit, _reason -> []
  end

  # Only supervisors answer `which_children`; asking anything else would
  # crash it with a FunctionClauseError.
  defp supervisor?(pid) do
    case Process.info(pid, :dictionary) do
      {:dictionary, dictionary} ->
        match?({:supervisor, _mod, _arity}, dictionary[:"$initial_call"])

      nil ->
        false
    end
  end

  defp label(pid) do
    case Process.info(pid, :registered_name) do
      {:registered_name, name} when is_atom(name) -> inspect(name)
      _unnamed -> inspect(pid)
    end
  end

  defp closure([], acc), do: acc

  defp closure([name | rest], acc) do
    if MapSet.member?(acc, name) do
      closure(rest, acc)
    else
      closure((Application.spec(name, :applications) || []) ++ rest, MapSet.put(acc, name))
    end
  end
end
