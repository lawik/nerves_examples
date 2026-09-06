defmodule HelloLiveViewWeb.Format do
  @moduledoc """
  Number formatting for the desktop windows.

  Both windows that show BEAM figures need these, so they live here rather than
  being copied into each one. Everything is for reading at a glance: the exact
  digit of a reduction count has never been the point.
  """

  @kb 1024
  @mb 1024 * @kb
  @gb 1024 * @mb

  @doc """
  Bytes in the largest unit that still reads naturally.

      iex> HelloLiveViewWeb.Format.format_bytes(512)
      "512 B"
      iex> HelloLiveViewWeb.Format.format_bytes(1_572_864)
      "1.5 MB"
  """
  @spec format_bytes(non_neg_integer()) :: String.t()
  def format_bytes(bytes) when bytes < @kb, do: "#{bytes} B"
  def format_bytes(bytes) when bytes < @mb, do: "#{Float.round(bytes / @kb, 1)} kB"
  def format_bytes(bytes) when bytes < @gb, do: "#{Float.round(bytes / @mb, 1)} MB"
  def format_bytes(bytes), do: "#{Float.round(bytes / @gb, 2)} GB"

  @doc """
  A plain count, abbreviated once it stops being readable. Counts below 10,000
  are left alone — "9999" tells you more than "10.0k".

      iex> HelloLiveViewWeb.Format.format_count(1234)
      "1234"
      iex> HelloLiveViewWeb.Format.format_count(1_204_800)
      "1.2M"
      iex> HelloLiveViewWeb.Format.format_count(12_345_678)
      "12.3M"
  """
  @spec format_count(non_neg_integer()) :: String.t()
  def format_count(n) when n < 10_000, do: Integer.to_string(n)
  def format_count(n) when n < 1_000_000, do: "#{Float.round(n / 1_000, 1)}k"
  def format_count(n) when n < 1_000_000_000, do: "#{Float.round(n / 1_000_000, 1)}M"
  def format_count(n), do: "#{Float.round(n / 1_000_000_000, 1)}G"
end
