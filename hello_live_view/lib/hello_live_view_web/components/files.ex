defmodule HelloLiveViewWeb.Components.Files do
  @moduledoc """
  The Files window, a Tracker for the device's filesystem; the editor it
  opens text files in; and the alert for a file it cannot open.

  Stateless, like the rest of the desktop. The LiveView owns the listing and
  what has been typed into each editor (`HelloLiveView.Files` does the
  reading and writing) and hands them down; these only lay them out.
  """
  use Phoenix.Component

  import HelloLiveViewWeb.Components.Desktop, only: [haiku_icon: 1]
  import HelloLiveViewWeb.Format

  alias HelloLiveView.Files
  alias Phoenix.LiveView.JS

  @doc """
  The window id for a file, as used by `HelloLiveView.Windows`: one per file
  for the editor (`:edit`) and one for the alert saying it cannot be opened
  (`:alert`). The path is encoded so the id is safe in the DOM and as a
  `phx-value`, and `file_window_path/1` gets it back.
  """
  @spec file_window_id(:edit | :alert, Path.t()) :: String.t()
  def file_window_id(kind, path) when kind in [:edit, :alert],
    do: "#{kind}-#{Base.url_encode64(path, padding: false)}"

  @doc "The path behind a window id from `file_window_id/2`."
  @spec file_window_path(String.t()) :: {:ok, Path.t()} | :error
  def file_window_path("edit-" <> encoded), do: Base.url_decode64(encoded, padding: false)
  def file_window_path("alert-" <> encoded), do: Base.url_decode64(encoded, padding: false)
  def file_window_path(_id), do: :error

  @doc """
  Why a file operation failed, in words.

  Covers the reasons `HelloLiveView.Files` adds on top of POSIX; anything
  else is spelled out by `:file.format_error/1`.
  """
  @spec reason_text(atom()) :: String.t()
  def reason_text(:not_text), do: "it is not a text file"
  def reason_text(:too_large), do: "it is larger than #{format_bytes(Files.max_text_bytes())}"
  def reason_text(:not_a_file), do: "it is not a regular file"
  def reason_text(:read_only), do: "this location is read-only"
  def reason_text(:invalid_name), do: "that is not a valid name"
  def reason_text(:eexist), do: "something with that name already exists"
  def reason_text(reason) when is_atom(reason), do: reason |> :file.format_error() |> to_string()

  @doc """
  The body of the Files window: the path as clickable segments, the form for
  a new file or folder while one is being named, and the listing.

  `files` is nil until the LiveView has read the directory.
  """
  attr :files, :map, default: nil, doc: "from HelloLiveView.Files.list/1"
  attr :new, :atom, default: nil, doc: ":file or :directory while the naming form is up"
  attr :notice, :string, default: nil, doc: "why the last action failed"

  def file_browser(%{files: nil} = assigns) do
    ~H"""
    <p class="p-4 text-center text-be-ink-soft">Reading…</p>
    """
  end

  def file_browser(assigns) do
    assigns =
      assign(assigns,
        crumbs: crumbs(assigns.files.path),
        roots: Enum.join(Files.writable_roots(), " and ")
      )

    ~H"""
    <div class="flex h-full min-h-0 flex-col">
      <div class="be-path">
        <button
          type="button"
          class="be-btn be-btn--icon"
          phx-click="fs_browse"
          phx-value-path={@files.parent}
          disabled={is_nil(@files.parent)}
          title="Up one level"
          aria-label="Up one level"
        >
          <.haiku_icon name="go-up" size={16} />
        </button>
        <nav class="be-doc be-path__crumbs" aria-label="Path">
          <button
            :for={{label, path} <- @crumbs}
            type="button"
            class="be-path__crumb"
            phx-click="fs_browse"
            phx-value-path={path}
            aria-current={if path == @files.path, do: "location", else: "false"}
          >
            {label}
          </button>
        </nav>
        <span class={["be-tag shrink-0", if(@files.writable?, do: "be-tag--ok", else: "be-tag--idle")]}>
          {if @files.writable?, do: "writable", else: "read-only"}
        </span>
      </div>

      <form :if={@new} class="be-newform" phx-submit="fs_create">
        <input type="hidden" name="kind" value={@new} />
        <label for="fs-new-name" class="shrink-0 text-[12px] font-semibold">
          New {if @new == :file, do: "file", else: "folder"}
        </label>
        <input
          id="fs-new-name"
          type="text"
          name="name"
          class="be-input"
          placeholder="name"
          autocomplete="off"
          required
          phx-mounted={JS.focus()}
        />
        <button type="submit" class="be-btn be-btn--default">Create</button>
        <button type="button" class="be-btn" phx-click="fs_cancel">Cancel</button>
      </form>

      <p :if={@notice} class="mb-2">
        <span class="be-tag be-tag--warn normal-case">{@notice}</span>
      </p>

      <p :if={@files.error} class="be-doc p-4 text-center text-be-ink-soft">
        Cannot open <span class="be-mono">{@files.path}</span>: {reason_text(@files.error)}.
      </p>

      <div :if={is_nil(@files.error)} class="be-doc be-table-wrap">
        <table class="be-table be-table--browse">
          <thead>
            <tr>
              <th><span>Name</span></th>
              <th class="be-table__num"><span>Size</span></th>
              <th><span>Modified</span></th>
            </tr>
          </thead>
          <tbody>
            <tr :if={@files.entries == []}>
              <td colspan="3" class="text-center text-be-ink-soft">Empty folder</td>
            </tr>
            <.entry_row :for={entry <- @files.entries} entry={entry} />
          </tbody>
        </table>
      </div>

      <div class="mt-2 flex shrink-0 flex-wrap items-center gap-x-3 text-[11px] text-be-ink-soft">
        <span :if={is_nil(@files.error)}>{length(@files.entries)} items</span>
        <span :if={not @files.writable?}>Files can be created under {@roots}.</span>
      </div>
    </div>
    """
  end

  # One row: a folder enters it, a file opens it, anything else (a device,
  # a socket, a dangling link) is listed but goes nowhere.
  attr :entry, :map, required: true, doc: "HelloLiveView.Files.entry()"

  defp entry_row(assigns) do
    ~H"""
    <tr
      phx-click={row_event(@entry.type)}
      phx-value-path={@entry.path}
      aria-disabled={to_string(@entry.type == :other)}
      title={@entry.path}
    >
      <td class="be-table__name">
        <span class="be-entry">
          <.haiku_icon name={entry_icon(@entry.type)} size={16} />
          <span>{@entry.name}</span>
          <span :if={@entry.link?} class="font-normal text-be-ink-soft" title="symbolic link">
            →
          </span>
        </span>
      </td>
      <td class="be-table__num">
        {if @entry.type == :file and @entry.size, do: format_bytes(@entry.size), else: "—"}
      </td>
      <td class="be-mono">
        {if @entry.mtime, do: Calendar.strftime(@entry.mtime, "%Y-%m-%d %H:%M"), else: "—"}
      </td>
    </tr>
    """
  end

  defp row_event(:directory), do: "fs_browse"
  defp row_event(:file), do: "fs_open"
  defp row_event(:other), do: nil

  defp entry_icon(:directory), do: "folder"
  defp entry_icon(:file), do: "text-x-generic"
  defp entry_icon(:other), do: "application-octet-stream"

  # "/data/logs" -> [{"/", "/"}, {"data", "/data"}, {"logs", "/data/logs"}]
  defp crumbs(path) do
    {crumbs, _path} =
      path
      |> Path.split()
      |> tl()
      |> Enum.map_reduce("/", fn segment, parent ->
        full = Path.join(parent, segment)
        {{segment, full}, full}
      end)

    [{"/", "/"} | crumbs]
  end

  @doc """
  The body of an editor window: where the file is, whether it has changed,
  and the text itself.

  The form carries the window id so the LiveView knows which editor is
  talking. Typing is reported (debounced) so the server's copy never falls
  far behind what is on screen; Save is a submit button in the window's
  menu bar, associated with this form by id, so it always sends the whole
  text.
  """
  attr :id, :string, required: true, doc: "the window id"
  attr :editor, :map, required: true, doc: "%{path:, name:, text:, saved:, writable?:, status:}"

  def text_editor(assigns) do
    assigns = assign(assigns, :dirty?, assigns.editor.text != assigns.editor.saved)

    ~H"""
    <form id={editor_form_id(@id)} class="be-editor" phx-change="edit_change" phx-submit="edit_save">
      <input type="hidden" name="window" value={@id} />
      <div class="be-editor__status">
        <span class="be-mono min-w-0 flex-1 truncate" title={@editor.path}>{@editor.path}</span>
        <span :if={not @editor.writable?} class="be-tag be-tag--idle">read-only</span>
        <span :if={@dirty?} class="be-tag be-tag--warn">modified</span>
        <span :if={@editor.status} class="shrink-0 text-be-ink-soft">{@editor.status}</span>
      </div>
      <textarea
        name="text"
        class="be-editor__text"
        phx-debounce="300"
        readonly={not @editor.writable?}
        spellcheck="false"
        wrap="off"
        aria-label={"Contents of #{@editor.name}"}
      >{@editor.text}</textarea>
    </form>
    """
  end

  @doc "The DOM id of an editor window's form, for a Save button outside it."
  @spec editor_form_id(String.t()) :: String.t()
  def editor_form_id(window_id), do: window_id <> "-form"

  @doc "The body of the alert for a file that has no viewer here."
  attr :id, :string, required: true, doc: "the window id, so OK can close it"
  attr :alert, :map, required: true, doc: "%{path:, name:, reason:}"

  def no_viewer(assigns) do
    ~H"""
    <div class="flex items-start gap-4">
      <.haiku_icon name="dialog-warning" size={40} />
      <div class="min-w-0 flex-1">
        <p class="text-[13px] font-bold">There is no viewer for {@alert.name}.</p>
        <p class="mt-1 text-be-ink-soft">
          {@alert.reason |> reason_text() |> String.capitalize()}.
        </p>
        <p class="be-mono mt-2 break-all text-[11px] text-be-ink-soft">{@alert.path}</p>
      </div>
    </div>
    <div class="mt-4 flex justify-end">
      <button type="button" class="be-btn be-btn--default" phx-click="close" phx-value-id={@id}>
        OK
      </button>
    </div>
    """
  end
end
