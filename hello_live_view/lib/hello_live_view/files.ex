defmodule HelloLiveView.Files do
  @moduledoc """
  The device's filesystem, in a shape the Files window can show, and the few
  things that window is allowed to do to it.

  A Nerves device boots from a read-only squashfs. Only two places take
  writes: `/data`, the application partition that survives reboots and
  firmware updates, and `/tmp`, which is RAM. Rather than probe mount flags
  this module simply knows that (`writable_roots/0`), and the window uses it
  to offer New File and New Folder only where they would work. On the host
  the same rule applies, so a demo browses the build machine read-only and
  can only scribble under `/tmp`. Add roots with

      config :hello_live_view, writable_paths: ["/data", "/tmp", "/mnt/usb"]

  Browsing is allowed everywhere. Opening a file means reading it: anything
  that passes `String.printable?/1` is text and goes to the editor, and
  anything else has no viewer here. Files over `max_text_bytes/0` are not
  read at all, so a click on a firmware image cannot fill the BEAM.
  """

  @writable ["/data", "/tmp"]
  @max_text_bytes 512 * 1024

  @type entry :: %{
          name: String.t(),
          path: Path.t(),
          type: :directory | :file | :other,
          link?: boolean(),
          size: non_neg_integer() | nil,
          mtime: DateTime.t() | nil
        }

  @type listing :: %{
          path: Path.t(),
          parent: Path.t() | nil,
          writable?: boolean(),
          entries: [entry()],
          error: File.posix() | nil
        }

  @type read_error :: :not_text | :too_large | :not_a_file | File.posix()
  @type write_error :: :read_only | :invalid_name | File.posix()

  @doc "The directories under which files may be created and written."
  @spec writable_roots() :: [Path.t()]
  def writable_roots, do: Application.get_env(:hello_live_view, :writable_paths, @writable)

  @doc "The most a file may weigh and still open in the editor."
  @spec max_text_bytes() :: pos_integer()
  def max_text_bytes, do: @max_text_bytes

  @doc """
  Whether a path may be written to.

  Decided by where the path is, not by asking the filesystem: a path is
  writable when it sits under one of the `writable_roots/0`. `..` is
  resolved first, so `/data/../etc` is `/etc` and read-only.
  """
  @spec writable?(Path.t()) :: boolean()
  def writable?(path) do
    path = Path.expand(path)
    Enum.any?(writable_roots(), &(path == &1 or String.starts_with?(path, &1 <> "/")))
  end

  @doc """
  What is in a directory, folders first and then files, each sorted by name.

  A directory that cannot be read still comes back as a listing, with the
  reason in `:error` and no entries, so the window can say what went wrong
  and still offer the way up.
  """
  @spec list(Path.t()) :: listing()
  def list(path) do
    path = Path.expand(path)

    listing = %{
      path: path,
      parent: parent(path),
      writable?: writable?(path),
      entries: [],
      error: nil
    }

    case File.ls(path) do
      {:ok, names} ->
        entries =
          names
          |> Enum.map(&describe(path, &1))
          |> Enum.sort_by(&{&1.type != :directory, String.downcase(&1.name)})

        %{listing | entries: entries}

      {:error, reason} ->
        %{listing | error: reason}
    end
  end

  @doc "The directory above, or nil at the root."
  @spec parent(Path.t()) :: Path.t() | nil
  def parent(path) do
    case Path.expand(path) do
      "/" -> nil
      expanded -> Path.dirname(expanded)
    end
  end

  @doc """
  Read a file as text.

  Only regular files are read, only up to `max_text_bytes/0`, and only
  contents that `String.printable?/1` accepts count as text. Everything else
  is an error the window turns into "there is no viewer for this".
  """
  @spec read(Path.t()) :: {:ok, String.t()} | {:error, read_error()}
  def read(path) do
    path = Path.expand(path)

    with {:ok, %File.Stat{type: :regular, size: size}} <- regular(path),
         :ok <- fits?(size),
         {:ok, content} <- File.read(path),
         # Files under /proc report a size of 0 and then read as much as they like.
         :ok <- fits?(byte_size(content)),
         true <- String.printable?(content) do
      {:ok, content}
    else
      false -> {:error, :not_text}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Replace a file's contents. Refused outside the writable roots."
  @spec write(Path.t(), String.t()) :: :ok | {:error, write_error()}
  def write(path, text) when is_binary(text) do
    path = Path.expand(path)

    with :ok <- ensure_writable(path) do
      File.write(path, text)
    end
  end

  @doc """
  Create an empty file or a directory inside `dir`.

  `name` is a single path segment: no slashes, not `.` or `..`, so nothing
  the browser sends can climb out of a writable root. Creating something
  that already exists fails with `:eexist` rather than touching it.
  """
  @spec create(Path.t(), String.t(), :file | :directory) ::
          {:ok, Path.t()} | {:error, write_error()}
  def create(dir, name, kind) when kind in [:file, :directory] do
    with :ok <- valid_name(name),
         path = Path.join(Path.expand(dir), name),
         :ok <- ensure_writable(path),
         :ok <- make(path, kind) do
      {:ok, path}
    end
  end

  # ------------------------------------------------------------------ private

  defp describe(dir, name) do
    path = Path.join(dir, name)
    entry = %{name: name, path: path, type: :other, link?: false, size: nil, mtime: nil}

    case File.lstat(path, time: :posix) do
      # Shown as what it points at, so a link to a folder can be entered.
      {:ok, %File.Stat{type: :symlink} = stat} ->
        %{entry | type: kind(target_type(path)), link?: true, mtime: at(stat.mtime)}

      {:ok, stat} ->
        %{entry | type: kind(stat.type), size: stat.size, mtime: at(stat.mtime)}

      {:error, _reason} ->
        entry
    end
  end

  defp target_type(path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: type}} -> type
      {:error, _dangling} -> :other
    end
  end

  defp kind(:directory), do: :directory
  defp kind(:regular), do: :file
  defp kind(_special), do: :other

  defp at(seconds) when is_integer(seconds), do: DateTime.from_unix!(seconds)
  defp at(_unknown), do: nil

  defp regular(path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular} = stat} -> {:ok, stat}
      {:ok, _not_regular} -> {:error, :not_a_file}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fits?(bytes) when bytes <= @max_text_bytes, do: :ok
  defp fits?(_bytes), do: {:error, :too_large}

  defp ensure_writable(path) do
    if writable?(path), do: :ok, else: {:error, :read_only}
  end

  defp valid_name(name) when name in ["", ".", ".."], do: {:error, :invalid_name}

  defp valid_name(name) when is_binary(name) do
    if String.valid?(name) and not String.contains?(name, ["/", <<0>>]),
      do: :ok,
      else: {:error, :invalid_name}
  end

  defp valid_name(_name), do: {:error, :invalid_name}

  defp make(path, :file), do: File.write(path, "", [:exclusive])
  defp make(path, :directory), do: File.mkdir(path)
end
