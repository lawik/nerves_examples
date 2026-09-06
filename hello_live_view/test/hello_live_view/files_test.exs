defmodule HelloLiveView.FilesTest do
  use ExUnit.Case, async: true

  alias HelloLiveView.Files

  # /tmp is a writable root on the host as well as on a device, so a folder
  # of its own under there is where each test may create things.
  setup do
    dir = Path.join("/tmp/hello_live_view_test", "files-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  test "writable?/1 knows the writable roots and resolves .. first" do
    assert Files.writable?("/data")
    assert Files.writable?("/data/logs/app.log")
    assert Files.writable?("/tmp")
    refute Files.writable?("/")
    refute Files.writable?("/etc/hosts")
    refute Files.writable?("/data/../etc/hosts")
    refute Files.writable?("/database")
  end

  test "list/1 puts folders first, then files, each sorted by name", %{dir: dir} do
    File.mkdir!(Path.join(dir, "zeta"))
    File.mkdir!(Path.join(dir, "Alpha"))
    File.write!(Path.join(dir, "notes.txt"), "hello")
    File.write!(Path.join(dir, "Banana.txt"), "")
    File.ln_s!(Path.join(dir, "zeta"), Path.join(dir, "link-to-zeta"))

    listing = Files.list(dir)
    assert listing.path == dir
    assert listing.parent == "/tmp/hello_live_view_test"
    assert listing.writable?
    assert listing.error == nil

    assert Enum.map(listing.entries, &{&1.name, &1.type}) == [
             {"Alpha", :directory},
             {"link-to-zeta", :directory},
             {"zeta", :directory},
             {"Banana.txt", :file},
             {"notes.txt", :file}
           ]

    notes = Enum.find(listing.entries, &(&1.name == "notes.txt"))
    assert notes.path == Path.join(dir, "notes.txt")
    assert notes.size == 5
    assert %DateTime{} = notes.mtime
    refute notes.link?

    # A link is shown as what it points at, so a linked folder can be entered.
    assert Enum.find(listing.entries, &(&1.name == "link-to-zeta")).link?
  end

  test "list/1 of a directory that cannot be read says why, and still knows the way up" do
    listing = Files.list("/no/such/place")
    assert listing.error == :enoent
    assert listing.entries == []
    assert listing.parent == "/no/such"
    refute listing.writable?
  end

  test "the root has no parent" do
    assert Files.parent("/") == nil
    assert Files.parent("/data") == "/"
    assert Files.list("/").parent == nil
  end

  test "create/3 makes empty files and folders, but only under a writable root", %{dir: dir} do
    assert {:ok, path} = Files.create(dir, "todo.txt", :file)
    assert path == Path.join(dir, "todo.txt")
    assert File.read!(path) == ""
    assert Files.create(dir, "todo.txt", :file) == {:error, :eexist}

    assert {:ok, sub} = Files.create(dir, "sub", :directory)
    assert File.dir?(sub)

    assert Files.create("/", "todo.txt", :file) == {:error, :read_only}
    assert Files.create("/etc", "sub", :directory) == {:error, :read_only}
    refute File.exists?("/todo.txt")
  end

  test "create/3 refuses names that are not a single path segment", %{dir: dir} do
    for name <- ["", ".", "..", "a/b", "../escape", <<0>>, <<0xFF>>] do
      assert Files.create(dir, name, :file) == {:error, :invalid_name}
    end

    assert File.ls!(dir) == []
  end

  test "read/1 returns text, and a reason for everything else", %{dir: dir} do
    text = Path.join(dir, "text.txt")
    File.write!(text, "hello\nwörld\n")
    assert Files.read(text) == {:ok, "hello\nwörld\n"}

    empty = Path.join(dir, "empty")
    File.write!(empty, "")
    assert Files.read(empty) == {:ok, ""}

    binary = Path.join(dir, "image.bin")
    File.write!(binary, <<0, 1, 2, 255>>)
    assert Files.read(binary) == {:error, :not_text}

    big = Path.join(dir, "big.log")
    File.write!(big, String.duplicate("x", Files.max_text_bytes() + 1))
    assert Files.read(big) == {:error, :too_large}

    assert Files.read(dir) == {:error, :not_a_file}
    assert Files.read(Path.join(dir, "missing")) == {:error, :enoent}
  end

  test "write/2 replaces a file's contents, only under a writable root", %{dir: dir} do
    path = Path.join(dir, "notes.txt")
    assert Files.write(path, "one\n") == :ok
    assert Files.write(path, "two\n") == :ok
    assert File.read!(path) == "two\n"

    assert Files.write("/etc/hosts", "gotcha") == {:error, :read_only}
  end
end
