defmodule HelloLiveView.Shell do
  @moduledoc """
  An IEx session for the desktop's IEx window, run the way the SSH console
  runs one.

  IEx never talks to a terminal directly. It sends `:io_request` messages to
  its group leader, whichever process that is, to print and to read a line.
  Over SSH the group leader is the SSH channel; here it is this process,
  which forwards what IEx prints to the window and answers its reads with
  what was typed there. Past that point it is the same `IEx.Server` and
  `IEx.Evaluator` the SSH console runs, reading the same `.iex.exs`, so the
  MOTD, Toolshed's helpers and `h/1` work exactly as they do over SSH.

  The owner is the process that started the shell, normally the LiveView. It
  receives:

    * `{:shell, pid, {:output, binary}}` for text IEx printed, ANSI codes
      and all, batched a few milliseconds at a time
    * `{:shell, pid, {:prompt, binary}}` when IEx is waiting for a line
    * `{:shell, pid, :exit}` when the session has ended

  and answers a prompt with `input/2`. `interrupt/1` does what Ctrl+C does
  in a terminal: the running evaluator is killed and IEx starts a fresh one,
  which is how a `ping/1` or a `Process.sleep/1` gets stopped. When the
  owner goes away, so does everything started here.

  There is no authentication in front of this window. It is an IEx prompt on
  the device for anyone who can reach the page, which is fine on a workshop
  bench and nowhere else.
  """

  use GenServer

  # Output is batched this long so a burst of prints is one message.
  @flush_after 25

  @type t :: pid()

  @doc "Start a session whose output goes to `owner`."
  @spec start(pid()) :: {:ok, t()} | {:error, term()}
  def start(owner \\ self()), do: GenServer.start(__MODULE__, owner)

  @doc "Answer the prompt with a line. A line typed while IEx is busy waits its turn."
  @spec input(t(), String.t()) :: :ok
  def input(shell, line) when is_binary(line), do: GenServer.cast(shell, {:input, line})

  @doc "Ctrl+C: kill whatever is running and start a fresh evaluator."
  @spec interrupt(t()) :: :ok
  def interrupt(shell), do: GenServer.cast(shell, :interrupt)

  @doc "End the session, if it has not ended already."
  @spec stop(t()) :: :ok
  def stop(shell) do
    GenServer.stop(shell)
  catch
    :exit, _already_gone -> :ok
  end

  @doc """
  The `.iex.exs` the session evaluates first.

  The firmware ships `/etc/iex.exs` (see `rootfs_overlay`), which is what
  the SSH console evaluates. On the host that file does not exist and the
  copy in `priv/` stands in: the same helpers, without the MOTD.
  """
  @spec dot_iex() :: String.t()
  def dot_iex do
    device = "/etc/iex.exs"

    if File.regular?(device),
      do: device,
      else: Application.app_dir(:hello_live_view, "priv/iex.exs")
  end

  # ------------------------------------------------------------------ server

  @impl true
  def init(owner) do
    Process.flag(:trap_exit, true)
    Process.monitor(owner)
    {:ok, _started} = Application.ensure_all_started(:iex)

    device = self()
    dot_iex = dot_iex()

    # IEx links itself to its group leader, so the two go down together.
    iex =
      spawn_link(fn ->
        Process.group_leader(self(), device)
        IEx.Server.run(dot_iex: dot_iex)
      end)

    {:ok, %{owner: owner, iex: iex, pending: nil, queue: :queue.new(), out: [], flush: nil}}
  end

  @impl true
  def handle_cast({:input, line}, state) do
    {:noreply, feed(%{state | queue: :queue.in(line, state.queue)})}
  end

  def handle_cast(:interrupt, state) do
    # IEx traps exits and treats this reason as a break: it kills the
    # evaluator, reports "interrupted" and starts a fresh one.
    Process.exit(state.iex, :interrupt)
    {:noreply, state}
  end

  @impl true
  def handle_info({:io_request, from, reply_as, request}, state) do
    {:noreply, io_request(request, from, reply_as, state)}
  end

  def handle_info(:flush, state), do: {:noreply, flush(%{state | flush: nil})}

  def handle_info({:EXIT, iex, _reason}, %{iex: iex} = state) do
    state = flush(state)
    send(state.owner, {:shell, self(), :exit})
    {:stop, :normal, state}
  end

  def handle_info({:EXIT, _other, _reason}, state), do: {:noreply, state}

  def handle_info({:DOWN, _ref, :process, owner, _reason}, %{owner: owner} = state) do
    {:stop, :normal, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  # Everything IEx started, and everything the evaluated code started, has
  # this process as its group leader. That includes an evaluator stuck in
  # a loop, which the polite `{:done, ...}` IEx sends it would not reach.
  @impl true
  def terminate(_reason, _state) do
    me = self()

    for pid <- Process.list(), pid != me, group_leader(pid) == me do
      Process.exit(pid, :kill)
    end

    :ok
  end

  # -------------------------------------------------------- the I/O protocol

  # Reads are answered later, from `feed/1`, once a line has been typed.
  defp io_request({:get_until, _encoding, prompt, mod, fun, args}, from, reply_as, state) do
    feed(%{state | pending: pending(from, reply_as, prompt, mod, fun, args)})
  end

  defp io_request({:get_line, _encoding, prompt}, from, reply_as, state) do
    feed(%{state | pending: pending(from, reply_as, prompt, __MODULE__, :__line__, [])})
  end

  defp io_request(request, from, reply_as, state) do
    {reply, state} = write_request(request, state)
    send(from, {:io_reply, reply_as, reply})
    state
  end

  defp write_request({:put_chars, encoding, chars}, state),
    do: {:ok, emit(state, text(encoding, chars))}

  defp write_request({:put_chars, encoding, mod, fun, args}, state),
    do: {:ok, emit(state, text(encoding, apply(mod, fun, args)))}

  defp write_request({:put_chars, chars}, state),
    do: write_request({:put_chars, :latin1, chars}, state)

  defp write_request({:put_chars, mod, fun, args}, state),
    do: write_request({:put_chars, :latin1, mod, fun, args}, state)

  # IEx installs its tab completion here; there is no line editor to use it.
  defp write_request({:setopts, _opts}, state), do: {:ok, state}
  defp write_request(:getopts, state), do: {[], state}
  # Without a size IEx wraps at 80 columns, which suits the window.
  defp write_request({:get_geometry, _what}, state), do: {{:error, :enotsup}, state}
  defp write_request({:get_chars, _encoding, _prompt, _count}, state), do: {:eof, state}

  defp write_request({:requests, requests}, state) do
    Enum.reduce(requests, {:ok, state}, fn request, {_reply, state} ->
      write_request(request, state)
    end)
  end

  defp write_request(_request, state), do: {{:error, :request}, state}

  @doc false
  def __line__(_continuation, :eof), do: {:done, :eof, []}
  def __line__(_continuation, chars), do: {:done, List.to_string(chars), []}

  defp pending(from, reply_as, prompt, mod, fun, args) do
    %{
      reply: {from, reply_as},
      prompt: IO.chardata_to_string(prompt),
      mod: mod,
      fun: fun,
      args: args,
      continuation: [],
      asked?: false
    }
  end

  # Hand queued lines to the pending read. IEx's parser says whether the
  # expression is complete; until it is, the next line is asked for with
  # the continuation prompt a terminal would show.
  defp feed(%{pending: nil} = state), do: state

  defp feed(%{pending: pending} = state) do
    case :queue.out(state.queue) do
      {:empty, _queue} ->
        ask(state)

      {{:value, line}, queue} ->
        state = %{state | queue: queue}
        chars = String.to_charlist(line <> "\n")

        case apply(pending.mod, pending.fun, [pending.continuation, chars | pending.args]) do
          {:done, result, _rest} ->
            {from, reply_as} = pending.reply
            send(from, {:io_reply, reply_as, result})
            %{state | pending: nil}

          {:more, continuation} ->
            more = %{pending | continuation: continuation, asked?: false}
            feed(%{state | pending: %{more | prompt: continuation_prompt(pending.prompt)}})
        end
    end
  end

  defp ask(%{pending: %{asked?: true}} = state), do: state

  defp ask(%{pending: pending} = state) do
    state = flush(state)
    send(state.owner, {:shell, self(), {:prompt, pending.prompt}})
    %{state | pending: %{pending | asked?: true}}
  end

  # "iex(3)> " continues as "...(3)> ", the way the tty shows it.
  defp continuation_prompt(prompt), do: Regex.replace(~r/^[^(\s]+(?=\()/, prompt, "...")

  # ------------------------------------------------------------------ output

  defp emit(state, text) do
    state = %{state | out: [state.out | text]}

    if state.flush do
      state
    else
      %{state | flush: Process.send_after(self(), :flush, @flush_after)}
    end
  end

  defp flush(%{out: []} = state), do: state

  defp flush(state) do
    send(state.owner, {:shell, self(), {:output, IO.iodata_to_binary(state.out)}})
    %{state | out: []}
  end

  defp text(:unicode, chars), do: IO.chardata_to_string(chars)
  defp text(:latin1, chars), do: :unicode.characters_to_binary(chars, :latin1, :unicode)

  defp group_leader(pid) do
    case Process.info(pid, :group_leader) do
      {:group_leader, leader} -> leader
      nil -> nil
    end
  end
end
