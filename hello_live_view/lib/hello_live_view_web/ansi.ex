defmodule HelloLiveViewWeb.ANSI do
  @moduledoc """
  Turns the ANSI escape codes IEx prints into spans the terminal window can
  style, and drops the rest.

  IEx colours its output when the VM has ANSI enabled, which it does on a
  device (`rel/vm.args.eex`), and the MOTD and Toolshed colour theirs. Rather
  than switch that off for the whole VM, which would also dim the SSH
  console, the codes are translated here: SGR sequences become classes for
  the sixteen colours, bold, italic and underline; other control sequences,
  cursor moves and screen clears, are removed; carriage returns are dropped.

  Output arrives in chunks that may cut a sequence or a styled run in half,
  so `to_html/2` takes the state in force at the end of the previous chunk
  and hands back the one in force at the end of this one.
  """

  @type state :: %{
          fg: 0..15 | nil,
          bg: 0..15 | nil,
          bold: boolean(),
          italic: boolean(),
          underline: boolean(),
          carry: binary()
        }

  @initial %{fg: nil, bg: nil, bold: false, italic: false, underline: false, carry: ""}

  # A complete control sequence (CSI or OSC), a lone escape, or a carriage return.
  @token ~r/\e\[[0-9;?]*[ -\/]*[@-~]|\e\][^\a\e]*(?:\a|\e\\)|\e.|\r/
  # An escape sequence the chunk ended in the middle of.
  @incomplete ~r/\e(?:\[[0-9;?]*[ -\/]*|\][^\a\e]*)?\z/

  @doc "The state before anything has been printed."
  @spec initial() :: state()
  def initial, do: @initial

  @doc "Escaped HTML for a chunk of terminal output, and the state it leaves behind."
  @spec to_html(binary(), state()) :: {binary(), state()}
  def to_html(chunk, state) do
    {text, carry} = split_incomplete(state.carry <> chunk)

    {html, state} =
      @token
      |> Regex.split(text, include_captures: true, trim: true)
      |> Enum.reduce({[], %{state | carry: carry}}, &token/2)

    {html |> Enum.reverse() |> IO.iodata_to_binary(), state}
  end

  defp split_incomplete(text) do
    case Regex.run(@incomplete, text, return: :index) do
      [{start, _length}] ->
        {binary_part(text, 0, start), binary_part(text, start, byte_size(text) - start)}

      nil ->
        {text, ""}
    end
  end

  defp token("\r", acc), do: acc

  defp token("\e[" <> rest = _csi, {html, state}) do
    if String.ends_with?(rest, "m") do
      params = rest |> String.trim_trailing("m") |> String.split(";") |> Enum.map(&param/1)
      {html, sgr(params, state)}
    else
      {html, state}
    end
  end

  defp token("\e" <> _other, acc), do: acc

  defp token(text, {html, state}) do
    escaped = Plug.HTML.html_escape_to_iodata(text)

    case classes(state) do
      [] ->
        {[escaped | html], state}

      classes ->
        {[[~s(<span class="), Enum.join(classes, " "), ~s(">), escaped, "</span>"] | html], state}
    end
  end

  defp param(""), do: 0

  defp param(digits) do
    case Integer.parse(digits) do
      {n, ""} -> n
      _other -> -1
    end
  end

  defp classes(state) do
    [
      state.bold && "ansi-b",
      state.italic && "ansi-i",
      state.underline && "ansi-u",
      state.fg && "ansi-fg-#{state.fg}",
      state.bg && "ansi-bg-#{state.bg}"
    ]
    |> Enum.filter(& &1)
  end

  # Select Graphic Rendition, the "m" sequences.
  defp sgr([], state), do: state
  defp sgr([0 | rest], state), do: sgr(rest, %{@initial | carry: state.carry})
  defp sgr([1 | rest], state), do: sgr(rest, %{state | bold: true})
  defp sgr([3 | rest], state), do: sgr(rest, %{state | italic: true})
  defp sgr([4 | rest], state), do: sgr(rest, %{state | underline: true})
  defp sgr([22 | rest], state), do: sgr(rest, %{state | bold: false})
  defp sgr([23 | rest], state), do: sgr(rest, %{state | italic: false})
  defp sgr([24 | rest], state), do: sgr(rest, %{state | underline: false})
  defp sgr([n | rest], state) when n in 30..37, do: sgr(rest, %{state | fg: n - 30})
  defp sgr([38, 5, n | rest], state) when n in 0..15, do: sgr(rest, %{state | fg: n})
  defp sgr([38, 5, _n | rest], state), do: sgr(rest, state)
  defp sgr([38, 2, _r, _g, _b | rest], state), do: sgr(rest, state)
  defp sgr([39 | rest], state), do: sgr(rest, %{state | fg: nil})
  defp sgr([n | rest], state) when n in 40..47, do: sgr(rest, %{state | bg: n - 40})
  defp sgr([48, 5, n | rest], state) when n in 0..15, do: sgr(rest, %{state | bg: n})
  defp sgr([48, 5, _n | rest], state), do: sgr(rest, state)
  defp sgr([48, 2, _r, _g, _b | rest], state), do: sgr(rest, state)
  defp sgr([49 | rest], state), do: sgr(rest, %{state | bg: nil})
  defp sgr([n | rest], state) when n in 90..97, do: sgr(rest, %{state | fg: n - 90 + 8})
  defp sgr([n | rest], state) when n in 100..107, do: sgr(rest, %{state | bg: n - 100 + 8})
  defp sgr([_unknown | rest], state), do: sgr(rest, state)
end
