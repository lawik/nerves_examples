defmodule HelloLiveViewWeb.Components.Text do
  @moduledoc """
  Typography helpers, dressed to match the BeOS chrome in
  `HelloLiveViewWeb.Components.Desktop`.
  """
  use Phoenix.Component

  @doc """
  A section heading inside a window body.
  """
  attr :title, :string, required: true
  slot :inner_block, doc: "optional supporting line under the title"

  def page_title(assigns) do
    ~H"""
    <header class="mb-3">
      <h1 class="text-[17px] font-bold tracking-tight text-be-ink">{@title}</h1>
      <p :if={@inner_block != []} class="mt-0.5 text-[12px] text-be-ink-soft">
        {render_slot(@inner_block)}
      </p>
    </header>
    """
  end

  @doc """
  A readable prose column.
  """
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def body(assigns) do
    ~H"""
    <div class={["max-w-prose text-[13px] leading-relaxed text-be-ink", @class]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  An outbound link.
  """
  attr :href, :string, required: true
  attr :rest, :global
  slot :inner_block, required: true

  def link_to(assigns) do
    ~H"""
    <a href={@href} class="be-link" target="_blank" rel="noopener" {@rest}>
      {render_slot(@inner_block)}
    </a>
    """
  end
end
