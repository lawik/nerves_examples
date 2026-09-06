defmodule HelloLiveView.DeviceInfo do
  @moduledoc """
  Basic facts about the device this firmware is running on — roughly the set
  `NervesMOTD` prints at the IEx prompt, shaped so a LiveView can render it.

  Everything degrades gracefully. `Nerves.Runtime`, `NervesMOTD` and
  `NervesTime` only exist on a target, so on the host (`mix phx.server`) the
  Nerves-specific fields come back `nil` and the BEAM- and OS-level ones still
  work. System memory, CPU usage and load come from OTP's `os_mon`; should it
  not be running they come back `nil` too. Nothing here raises.

  `read/0` takes a full snapshot, including a shell-out to `df`; call it every
  few seconds rather than every tick. `clock/0`, `uptime/0` and `cpu/0` are
  cheap and meant for a once-a-second refresh.
  """

  @app :hello_live_view

  # Loopback tells you nothing about a device's connectivity.
  @excluded_ifnames [~c"lo", ~c"lo0"]

  @doc "A complete snapshot of the device."
  @spec read() :: map()
  def read do
    %{
      firmware: firmware(),
      serial_number: maybe_call(Nerves.Runtime, :serial_number, []),
      hostname: hostname(),
      platform: platform(),
      clock: clock(),
      uptime: uptime(),
      applications: applications(),
      memory: memory(),
      storage: storage(),
      load_average: load_average(),
      temperature: temperature(),
      runtime: runtime(),
      networks: networks()
    }
  end

  # ------------------------------------------------------------------ firmware

  @doc "Firmware metadata out of the Nerves key-value store."
  @spec firmware() :: map()
  def firmware do
    # "adjective-noun (uuid)", the same nickname fwup and NervesMOTD use.
    id = maybe_call(NervesMOTD.Runtime.Target, :firmware_id, [])

    %{
      product: kv("nerves_fw_product") || to_string(@app),
      version: kv("nerves_fw_version") || app_version(),
      id: id,
      nickname: nickname_from_id(id),
      validity: firmware_validity(),
      partition: active_partition()
    }
  end

  # "brave-otter (5d3a...)" -> "brave-otter". The nickname alone tells two
  # builds apart at a glance, which is all a window title needs.
  @doc false
  @spec nickname_from_id(String.t() | nil) :: String.t() | nil
  def nickname_from_id(nil), do: nil
  def nickname_from_id("unknown"), do: nil
  def nickname_from_id(id), do: id |> String.split(" (", parts: 2) |> hd()

  @doc "hostname · firmware nickname, or just the hostname on a host."
  @spec title(map()) :: String.t()
  def title(device) do
    [device.hostname, device.firmware.nickname]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp firmware_validity do
    case maybe_call(Nerves.Runtime, :firmware_valid?, [], :unknown) do
      true -> :valid
      false -> :invalid
      _ -> :unknown
    end
  end

  defp active_partition do
    case maybe_call(Nerves.Runtime, :firmware_slots, []) do
      %{active: active} when is_binary(active) -> String.upcase(active)
      _ -> nil
    end
  end

  defp app_version do
    case Application.spec(@app, :vsn) do
      nil -> "0.0.0"
      vsn -> List.to_string(vsn)
    end
  end

  # -------------------------------------------------------------- identity

  @spec hostname() :: String.t()
  def hostname do
    case :inet.gethostname() do
      {:ok, name} -> List.to_string(name)
      _ -> "unknown"
    end
  end

  defp platform do
    case {kv("nerves_fw_platform"), kv("nerves_fw_architecture")} do
      {nil, _} -> List.to_string(:erlang.system_info(:system_architecture))
      {platform, nil} -> platform
      {platform, architecture} -> "#{platform} #{architecture}"
    end
  end

  # ----------------------------------------------------------- clock & uptime

  @doc "Local wall clock, plus whether NervesTime has synced it with NTP yet."
  @spec clock() :: map()
  def clock do
    %{
      time: NaiveDateTime.truncate(NaiveDateTime.local_now(), :second),
      # NervesTime is absent on the host; assume the laptop's clock is fine.
      synchronized?: maybe_call(NervesTime, :synchronized?, [], true)
    }
  end

  @doc "How long the BEAM has been up."
  @spec uptime() :: map()
  def uptime do
    {milliseconds, _since_last_call} = :erlang.statistics(:wall_clock)
    seconds = div(milliseconds, 1_000)
    {days, {hours, minutes, secs}} = :calendar.seconds_to_daystime(seconds)

    text =
      cond do
        days > 0 -> "#{days}d #{hours}h #{minutes}m"
        hours > 0 -> "#{hours}h #{minutes}m #{secs}s"
        minutes > 0 -> "#{minutes}m #{secs}s"
        true -> "#{secs}s"
      end

    %{text: text, seconds: seconds}
  end

  # ------------------------------------------------------------- applications

  defp applications do
    started = for {app, _description, _vsn} <- Application.started_applications(), do: app
    loaded = for {app, _description, _vsn} <- Application.loaded_applications(), do: app

    # The boot script knows what release_handler intended to start. If we can't
    # read it, the loaded set is close enough.
    expected = expected_started_apps() || loaded

    %{started: length(started), not_started: Enum.sort(expected -- started)}
  end

  defp expected_started_apps do
    {:ok, [[boot]]} = :init.get_argument(:boot)
    {:script, _name, instructions} = :erlang.binary_to_term(File.read!("#{boot}.boot"))

    for {:apply, {:application, :start_boot, [app | _]}} <- instructions, do: app
  rescue
    _ -> nil
  end

  # ------------------------------------------------------------------- memory

  # System memory comes from os_mon's memsup — /proc/meminfo on Linux, a port
  # program on macOS. BEAM memory always works, so report both.
  defp memory do
    %{system: system_memory(), beam_bytes: :erlang.memory(:total)}
  end

  defp system_memory do
    case maybe_call(:memsup, :get_system_memory_data, []) do
      data when is_list(data) -> memory_from_memsup(data)
      _ -> :error
    end
  end

  @mib 1024 * 1024

  # "Used" the way `free` means it: what the kernel could not hand out right
  # now. Linux reports that directly as available_memory; elsewhere it is
  # free plus buffers plus cache.
  @doc false
  def memory_from_memsup(data) do
    with total when is_integer(total) and total > 0 <-
           data[:system_total_memory] || data[:total_memory],
         available when is_integer(available) <- available_memory(data) do
      used = max(total - available, 0)

      {:ok,
       %{
         size_mb: round(total / @mib),
         used_mb: round(used / @mib),
         used_percent: round(used / total * 100)
       }}
    else
      _ -> :error
    end
  end

  defp available_memory(data) do
    case {data[:available_memory], data[:free_memory]} do
      {available, _free} when is_integer(available) ->
        available

      {_none, free} when is_integer(free) ->
        free + (data[:buffered_memory] || 0) + (data[:cached_memory] || 0)

      _ ->
        nil
    end
  end

  # ------------------------------------------------------------------ storage

  # On a target this is the application data partition; on the host, whatever
  # filesystem the project is sitting on. Either way we report the path we
  # measured so the number isn't ambiguous.
  defp storage do
    path =
      case kv("nerves_fw_application_part0_devpath") do
        devpath when is_binary(devpath) and devpath != "" -> devpath
        _ -> File.cwd!()
      end

    case disk_free(path) do
      {:ok, stats} -> Map.put(stats, :path, path)
      :error -> nil
    end
  end

  defp disk_free(path) do
    {output, 0} = System.cmd("df", ["-Pm", path])
    [_header, results_row | _] = String.split(output, "\n")
    [_filesystem, size_mb, used_mb, _available, used_percent | _] = String.split(results_row)

    {size_mb, ""} = Integer.parse(size_mb)
    {used_mb, ""} = Integer.parse(used_mb)
    {used_percent, "%"} = Integer.parse(used_percent)

    {:ok, %{size_mb: size_mb, used_mb: used_mb, used_percent: used_percent}}
  rescue
    _ -> :error
  end

  # ------------------------------------------------------- load & temperature

  # cpu_sup hands load averages back scaled by 256, the way the kernel does.
  defp load_average do
    with one when is_integer(one) <- maybe_call(:cpu_sup, :avg1, []),
         five when is_integer(five) <- maybe_call(:cpu_sup, :avg5, []),
         fifteen when is_integer(fifteen) <- maybe_call(:cpu_sup, :avg15, []) do
      Enum.map([one, five, fifteen], &:erlang.float_to_binary(&1 / 256, decimals: 2))
    else
      _ -> nil
    end
  end

  defp temperature do
    with {:ok, contents} <- File.read("/sys/class/thermal/thermal_zone0/temp"),
         {millidegrees_c, _rest} <- Integer.parse(String.trim(contents)) do
      Float.round(millidegrees_c / 1000, 1)
    else
      _ -> nil
    end
  end

  # ---------------------------------------------------------------------- cpu

  @doc "Whether cpu_sup is up, which is os_mon on a Unix it knows."
  @spec cpu_supported?() :: boolean()
  def cpu_supported?, do: is_pid(Process.whereis(:cpu_sup))

  @doc """
  CPU usage per core since the calling process last asked, in whole percents:

      %{total: 37, cores: [%{name: "cpu0", percent: 41}, ...]}

  This is `:cpu_sup.util/1`, so the measurement window belongs to the calling
  process: the first call a process makes is meaningless and should be thrown
  away, and two calls inside the same clock tick read 100%. Nil when os_mon is
  not running or does not support this OS.
  """
  @spec cpu() :: %{total: 0..100, cores: [map()]} | nil
  def cpu do
    case maybe_call(:cpu_sup, :util, [[:per_cpu]]) do
      cores when is_list(cores) -> cpu_from_util(cores)
      _ -> nil
    end
  end

  @doc false
  def cpu_from_util([]), do: nil

  def cpu_from_util(cores) do
    cores = Enum.sort_by(cores, &elem(&1, 0))
    busy = for {_index, busy, _non_busy, _misc} <- cores, do: busy

    %{
      total: round(Enum.sum(busy) / length(busy)),
      cores:
        for(
          {index, busy, _non_busy, _misc} <- cores,
          do: %{name: "cpu#{index}", percent: round(busy)}
        )
    }
  end

  # ------------------------------------------------------------------ runtime

  defp runtime do
    %{
      target: to_string(Application.get_env(@app, :target, :host)),
      elixir: System.version(),
      otp: List.to_string(:erlang.system_info(:otp_release)),
      processes: :erlang.system_info(:process_count),
      process_limit: :erlang.system_info(:process_limit),
      schedulers: :erlang.system_info(:schedulers_online)
    }
  end

  # ----------------------------------------------------------------- networks

  @doc "Every non-loopback interface that currently holds an address."
  @spec networks() :: [map()]
  def networks do
    case :inet.getifaddrs() do
      {:ok, interfaces} ->
        interfaces
        |> Enum.reject(fn {name, _ifaddrs} -> name in @excluded_ifnames end)
        |> Enum.map(&interface/1)
        |> Enum.reject(&(&1.addresses == []))
        # Interfaces carrying an IPv4 address first — on a laptop full of
        # tunnels, those are the ones anyone actually wants to read.
        |> Enum.sort_by(&{not routable?(&1), &1.name})

      _ ->
        []
    end
  end

  defp routable?(interface), do: Enum.any?(interface.addresses, &(&1.family == :inet))

  defp interface({name, ifaddrs}) do
    flags = Keyword.get(ifaddrs, :flags, [])

    %{
      name: List.to_string(name),
      up?: :up in flags and :running in flags,
      hwaddr: format_hwaddr(Keyword.get(ifaddrs, :hwaddr)),
      addresses: ifaddrs |> extract_addresses() |> Enum.map(&format_address/1)
    }
  end

  # :inet.getifaddrs/0 hands back a flat keyword list where each :addr is
  # immediately followed by its :netmask.
  defp extract_addresses(ifaddrs, acc \\ [])
  defp extract_addresses([], acc), do: Enum.reverse(acc)

  defp extract_addresses([{:addr, address}, {:netmask, netmask} | rest], acc),
    do: extract_addresses(rest, [{address, netmask} | acc])

  defp extract_addresses([_other | rest], acc), do: extract_addresses(rest, acc)

  defp format_address({address, netmask}) do
    %{
      text: "#{:inet.ntoa(address)}/#{prefix_length(netmask)}",
      family: if(tuple_size(address) == 4, do: :inet, else: :inet6)
    }
  end

  defp format_hwaddr(bytes) when is_list(bytes),
    do: Enum.map_join(bytes, ":", &String.downcase(Base.encode16(<<&1>>)))

  defp format_hwaddr(_), do: nil

  defp prefix_length({a, b, c, d}), do: leading_ones(<<a, b, c, d>>, 0)

  defp prefix_length({a, b, c, d, e, f, g, h}),
    do: leading_ones(<<a::16, b::16, c::16, d::16, e::16, f::16, g::16, h::16>>, 0)

  defp leading_ones(<<0b11111111, rest::binary>>, sum), do: leading_ones(rest, sum + 8)
  defp leading_ones(<<0b11111110, _rest::binary>>, sum), do: sum + 7
  defp leading_ones(<<0b11111100, _rest::binary>>, sum), do: sum + 6
  defp leading_ones(<<0b11111000, _rest::binary>>, sum), do: sum + 5
  defp leading_ones(<<0b11110000, _rest::binary>>, sum), do: sum + 4
  defp leading_ones(<<0b11100000, _rest::binary>>, sum), do: sum + 3
  defp leading_ones(<<0b11000000, _rest::binary>>, sum), do: sum + 2
  defp leading_ones(<<0b10000000, _rest::binary>>, sum), do: sum + 1
  defp leading_ones(_rest, sum), do: sum

  # ------------------------------------------------------------------ helpers

  defp kv(key), do: maybe_call(Nerves.Runtime.KV, :get_active, [key])

  # Nerves modules are compiled for targets only, so every call into them has to
  # survive the module simply not being there.
  defp maybe_call(module, function, args, default \\ nil) do
    if Code.ensure_loaded?(module) and function_exported?(module, function, length(args)) do
      apply(module, function, args)
    else
      default
    end
  rescue
    _ -> default
  catch
    _kind, _reason -> default
  end
end
