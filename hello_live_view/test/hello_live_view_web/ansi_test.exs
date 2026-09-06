defmodule HelloLiveViewWeb.ANSITest do
  use ExUnit.Case, async: true

  alias HelloLiveViewWeb.ANSI

  test "colours become classes and a reset ends them" do
    {html, state} = ANSI.to_html("a \e[31mred\e[0m b", ANSI.initial())

    assert html == ~s|a <span class="ansi-fg-1">red</span> b|
    assert state == ANSI.initial()
  end

  test "a style carries over into the next chunk" do
    {html, state} = ANSI.to_html("\e[1;34mbold blue", ANSI.initial())
    assert html == ~s|<span class="ansi-b ansi-fg-4">bold blue</span>|

    {html, _state} = ANSI.to_html(" still\e[0m done", state)
    assert html == ~s|<span class="ansi-b ansi-fg-4"> still</span> done|
  end

  test "a sequence cut by a chunk boundary is finished by the next" do
    {html, state} = ANSI.to_html("x\e[3", ANSI.initial())
    assert html == "x"

    {html, _state} = ANSI.to_html("2my", state)
    assert html == ~s|<span class="ansi-fg-2">y</span>|
  end

  test "bright colours, 256-colour picks and unknown codes" do
    {html, _} =
      ANSI.to_html("\e[93mwarn\e[39m \e[38;5;12mblue\e[0m \e[38;5;200mx\e[0m", ANSI.initial())

    assert html == ~s|<span class="ansi-fg-11">warn</span> <span class="ansi-fg-12">blue</span> x|
  end

  test "other control sequences and carriage returns go, text is escaped" do
    {html, _} = ANSI.to_html("\e[2J\e[H<b>\r\n\e]0;title\a", ANSI.initial())
    assert html == "&lt;b&gt;\n"
  end
end
