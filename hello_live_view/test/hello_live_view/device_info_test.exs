defmodule HelloLiveView.DeviceInfoTest do
  use ExUnit.Case, async: true

  alias HelloLiveView.DeviceInfo

  @mib 1024 * 1024

  describe "cpu_from_util/1" do
    test "rounds each core and averages them for the machine, in core order" do
      util = [{1, 10.4, 89.6, []}, {0, 75.5, 24.5, []}]

      assert DeviceInfo.cpu_from_util(util) == %{
               total: 43,
               cores: [%{name: "cpu0", percent: 76}, %{name: "cpu1", percent: 10}]
             }
    end

    test "has nothing to say about no cores" do
      assert DeviceInfo.cpu_from_util([]) == nil
    end
  end

  describe "memory_from_memsup/1" do
    test "trusts the kernel's own idea of available memory when it has one" do
      data = [
        system_total_memory: 4096 * @mib,
        free_memory: 100 * @mib,
        buffered_memory: 50 * @mib,
        cached_memory: 50 * @mib,
        available_memory: 3072 * @mib
      ]

      assert DeviceInfo.memory_from_memsup(data) ==
               {:ok, %{size_mb: 4096, used_mb: 1024, used_percent: 25}}
    end

    test "otherwise counts buffers and cache as free, the way `free` does" do
      data = [
        total_memory: 1024 * @mib,
        free_memory: 256 * @mib,
        buffered_memory: 128 * @mib,
        cached_memory: 128 * @mib
      ]

      assert DeviceInfo.memory_from_memsup(data) ==
               {:ok, %{size_mb: 1024, used_mb: 512, used_percent: 50}}
    end

    test "is an error without a total to measure against" do
      assert DeviceInfo.memory_from_memsup(free_memory: 1) == :error
      assert DeviceInfo.memory_from_memsup([]) == :error
    end
  end

  test "cpu, memory and load all come from os_mon on this host" do
    assert DeviceInfo.cpu_supported?()
    assert %{total: total, cores: [%{name: "cpu0"} | _]} = DeviceInfo.cpu()
    assert total in 0..100

    device = DeviceInfo.read()
    assert {:ok, %{used_percent: percent}} = device.memory.system
    assert percent in 0..100
    assert [_one, _five, _fifteen] = device.load_average
  end
end
