defmodule TusPlug.Test do
  @moduledoc false
  use ExUnit.Case, async: true

  use Plug.Test

  alias TusPlug, as: TusPlug

  setup_all do
    on_exit(fn ->
      path =
        Application.get_env(:tus_plug, TusPlug)
        |> Keyword.get(:upload_path)

      path
      |> File.ls!()
      |> Enum.filter(fn file -> file != ".gitignore" end)
      |> Enum.each(fn file ->
        path
        |> Path.join(file)
        |> File.rm!()
      end)
    end)

    :ok
  end

  test "not matching path just returns conn" do
    c = conn(:get, "/foo/var")
    conn = TusPlug.call(c, TusPlug.init([]))

    assert conn == c
  end

  describe "HEAD" do
    test "happy path" do
      # fixture
      :ok = empty_file_fixture("stuff")

      # test
      newconn =
        conn(:head, "#{upload_baseurl()}/stuff")
        |> put_req_header("tus-resumable", "1.0.0")

      opts = TusPlug.init([])
      newconn = newconn |> TusPlug.call(opts)

      assert {200, _headers, _body} = sent_resp(newconn)

      assert_upload_offset(newconn)
      assert_cache_control(newconn)
      assert_tus_resumable(newconn)
      assert_tus_extensions(newconn)
    end

    test "file not found" do
      newconn =
        conn(:head, "#{upload_baseurl()}/yadda.gz")
        |> put_req_header("tus-resumable", "1.0.0")

      opts = TusPlug.init([])
      newconn = newconn |> TusPlug.call(opts)

      assert {404, _headers, _body} = sent_resp(newconn)

      assert_cache_control(newconn)
      assert_tus_resumable(newconn)
      assert_tus_extensions(newconn)
    end
  end

  describe "PATCH" do
    test "happy path" do
      # fixture
      filename = "patch.happy"
      :ok = empty_file_fixture(filename)

      body = "yadda"

      newconn =
        conn(:patch, "#{upload_baseurl()}/#{filename}", body)
        |> put_req_header("upload-offset", "0")
        |> put_req_header("tus-resumable", "1.0.0")
        |> put_req_header("content-type", "application/offset+octet-stream")

      opts = TusPlug.init([])
      newconn = newconn |> TusPlug.call(opts)

      assert {204, _headers, _body} = sent_resp(newconn)

      assert_upload_offset(newconn, body |> byte_size() |> to_string())
      assert_tus_resumable(newconn)
      assert_tus_extensions(newconn)

      # upload info should not be there
      refute newconn.private[TusPlug.Upload]
    end

    test "multiple requests" do
      # fixture
      filename = "patch.multiple"
      :ok = empty_file_fixture(filename)

      # first segment
      body = "yadda"

      {:ok, _, res} = upload_chunk(filename, body, "0")
      assert {204, _headers, _body} = res

      # 2nd segment
      body2 = "baz"

      {:ok, newconn2, res} = upload_chunk(filename, body2, "5")
      assert {204, _headers, _body} = res

      # checks
      assert_upload_offset(newconn2, (body <> body2) |> byte_size() |> to_string())
      assert body <> body2 == File.read!(tmp_file(filename))
      assert_tus_resumable(newconn2)
      assert_tus_extensions(newconn2)

      # upload info should not be there
      refute newconn2.private[TusPlug.Upload]
    end

    test "completed upload" do
      # fixture
      filename = "patch.completed"
      :ok = empty_file_fixture(filename, 8)

      # first segment
      body = "yadda"

      {:ok, _, res} = upload_chunk(filename, body, "0")
      assert {204, _headers, _body} = res

      # 2nd segment
      body2 = "baz"

      {:ok, newconn2, res} = upload_chunk(filename, body2, "5")
      assert {204, _headers, _body} = res

      expected = %TusPlug.Upload{filename: filename, path: tmp_file(filename)}
      assert newconn2.private[TusPlug.Upload] == expected

      assert nil == newconn2.private[TusPlug.Upload] |> Map.get(:metadata)
    end

    test "completed upload, with metadata" do
      # fixture
      filename = "patch.completed_with_metadata"

      # create an entry into the cache
      alias TusPlug.Cache
      alias TusPlug.Cache.Entry
      filename |> tmp_file() |> File.touch!()

      {:ok, _} =
        %Entry{
          id: filename,
          filename: filename,
          started_at: DateTime.utc_now(),
          size: 8,
          metadata: [{"foo", "YmFy"}, {"bar", "YmF6"}]
        }
        |> Cache.put()

      # first segment
      body = "yadda"

      {:ok, _, res} = upload_chunk(filename, body, "0")
      assert {204, _headers, _body} = res

      # 2nd segment
      body2 = "baz"

      {:ok, newconn2, res} = upload_chunk(filename, body2, "5")
      assert {204, _headers, _body} = res

      assert %TusPlug.Upload{} = upload_info = newconn2.private[TusPlug.Upload]
      assert upload_info.filename == filename
      assert upload_info.path == tmp_file(filename)
      assert [{"foo", "YmFy"}, {"bar", "YmF6"}] = upload_info.metadata
    end

    test "full upload with method override" do
      # fixture
      filename = "patch.override"
      :ok = empty_file_fixture(filename, 8)

      # first segment
      body = "yadda"

      newconn =
        conn(:post, "#{upload_baseurl()}/#{filename}", body)
        |> put_req_header("upload-offset", "0")
        |> put_req_header("x-http-method-override", "PATCH")
        |> put_req_header("tus-resumable", "1.0.0")
        |> put_req_header("content-type", "application/offset+octet-stream")

      opts = TusPlug.init([])
      newconn = newconn |> TusPlug.call(opts)

      assert {204, _headers, _body} = sent_resp(newconn)

      # 2nd segment
      body = "baz"

      newconn2 =
        conn(:post, "#{upload_baseurl()}/#{filename}", body)
        |> put_req_header("upload-offset", "5")
        |> put_req_header("x-http-method-override", "PATCH")
        |> put_req_header("tus-resumable", "1.0.0")
        |> put_req_header("content-type", "application/offset+octet-stream")

      opts = TusPlug.init([])
      newconn2 = newconn2 |> TusPlug.call(opts)

      assert {204, _headers, _body} = sent_resp(newconn2)

      expected = %TusPlug.Upload{filename: filename, path: tmp_file(filename)}
      assert newconn2.private[TusPlug.Upload] == expected
    end

    test "exceeds declared size" do
      # fixture
      filename = "patch.toomuch"
      :ok = empty_file_fixture(filename, 6)

      # first segment
      body = "yadda"

      {:ok, _, res} = upload_chunk(filename, body, "0")
      assert {204, _headers, _body} = res

      # 2nd segment
      body2 = "baz"

      {:ok, _, res} = upload_chunk(filename, body2, "5")
      assert {413, _headers, _body} = res
    end

    test "file does not exists" do
      newconn =
        conn(:patch, "#{upload_baseurl()}/notfound", "body")
        |> put_req_header("upload-offset", "0")
        |> put_req_header("tus-resumable", "1.0.0")
        |> put_req_header("content-type", "application/offset+octet-stream")

      opts = TusPlug.init([])
      newconn = newconn |> TusPlug.call(opts)

      assert {404, _headers, _body} = sent_resp(newconn)

      assert_tus_resumable(newconn)
      assert_tus_extensions(newconn)
    end

    test "conflict" do
      # fixture
      filename = "patch.conflict"
      :ok = empty_file_fixture(filename)

      {:ok, _, _} = upload_chunk(filename, "somedata", "0")

      # overlapping
      {:ok, newconn2, res} = upload_chunk(filename, "dataother", "5")

      # assert conflict
      assert {409, _headers, _body} = res

      assert_tus_resumable(newconn2)
      assert_tus_extensions(newconn2)
    end

    test "upload expires" do
      # fixture
      filename = "patch.expires"
      :ok = empty_file_fixture(filename)

      # first segment
      body = "yadda"
      {:ok, newconn, res} = upload_chunk(filename, body, "0")
      assert {204, _headers, _body} = res
      assert_upload_expires(newconn)

      # this is cheating since I rely on an internal message
      future =
        DateTime.utc_now()
        |> Timex.add(Timex.Duration.from_seconds(10))

      TusPlug.Cache |> GenServer.whereis() |> send({:expire_timer, future})

      # 2nd segment
      body2 = "baz"

      {:ok, _, res} = upload_chunk(filename, body2, "5")
      assert {404, _headers, _body} = res
    end
  end

  describe "POST" do
    test "happy path" do
      newconn =
        conn(:post, "#{upload_baseurl()}")
        |> put_req_header("upload-length", "42")
        |> put_req_header("tus-resumable", "1.0.0")

      opts = TusPlug.init([])
      newconn = newconn |> TusPlug.call(opts)

      assert {201, _headers, _body} = sent_resp(newconn)

      assert_tus_resumable(newconn)
      assert_tus_extensions(newconn)
      assert_tus_location(newconn)
      assert_upload_expires(newconn)
    end

    test "wrong path" do
      newconn =
        conn(:post, "#{upload_baseurl()}/foo")
        |> put_req_header("upload-length", "42")
        |> put_req_header("tus-resumable", "1.0.0")

      opts = TusPlug.init([])
      newconn = newconn |> TusPlug.call(opts)

      assert {404, _headers, _body} = sent_resp(newconn)

      assert_tus_resumable(newconn)
      assert_tus_extensions(newconn)
    end

    test "missing upload-length" do
      newconn =
        conn(:post, "#{upload_baseurl()}")
        |> put_req_header("tus-resumable", "1.0.0")

      opts = TusPlug.init([])
      newconn = newconn |> TusPlug.call(opts)

      assert {412, _headers, _body} = sent_resp(newconn)

      assert_tus_resumable(newconn)
      assert_tus_extensions(newconn)
    end

    test "413 too large" do
      len =
        get_tus_max_size()
        |> Kernel.+(1)

      newconn =
        conn(:post, "#{upload_baseurl()}")
        |> put_req_header("upload-length", "#{len}")
        |> put_req_header("tus-resumable", "1.0.0")

      opts = TusPlug.init([])
      newconn = newconn |> TusPlug.call(opts)

      assert {413, _headers, _body} = sent_resp(newconn)
      assert_tus_max_size(newconn)
    end

    test "with metadata" do
      alias TusPlug.POST

      postconn =
        conn(:post, "#{upload_baseurl()}")
        |> put_req_header("upload-length", "42")
        |> put_req_header("upload-metadata", gen_metadata())
        |> put_req_header("tus-resumable", "1.0.0")

      opts = TusPlug.init([])
      postconn = postconn |> TusPlug.call(opts)

      assert {201, _headers, _body} = sent_resp(postconn)

      loc = get_header(postconn, "location")

      headconn =
        conn(:head, loc)
        |> put_req_header("tus-resumable", "1.0.0")

      opts = TusPlug.init([])
      headconn = headconn |> TusPlug.call(opts)
      assert {200, _headers, _body} = sent_resp(headconn)

      assert metadata = get_header(headconn, "upload-metadata")
      assert {:ok, _} = POST.validate_metadata(metadata)
    end
  end

  describe "OPTIONS" do
    test "options" do
      newconn = conn(:options, "#{upload_baseurl()}")

      opts = TusPlug.init([])
      newconn = newconn |> TusPlug.call(opts)

      assert {204, _headers, _body} = sent_resp(newconn)
      assert_tus_resumable(newconn)
      assert_tus_version(newconn)
      assert_tus_extensions(newconn)
      assert_tus_max_size(newconn)
    end
  end

  defp assert_tus_location(conn) do
    assert get_header(conn, "location") =~ ~r/#{upload_baseurl()}\/[a-z|0-9]{32}$/
  end

  defp assert_tus_extensions(conn) do
    extensions = ["creation", "expiration"] |> Enum.join(",")
    assert extensions == get_header(conn, "tus-extension")
  end

  defp assert_cache_control(conn) do
    assert "no-store" = get_header(conn, "cache-control")
  end

  defp assert_tus_resumable(conn) do
    version = Application.get_env(:tus_plug, :version, "1.0.0")
    assert version == get_header(conn, "tus-resumable")
  end

  defp assert_tus_version(conn) do
    version = Application.get_env(:tus_plug, :version, "1.0.0")
    assert version == get_header(conn, "tus-version")
  end

  defp assert_upload_offset(conn, value \\ 0) do
    assert offset = get_header(conn, "upload-offset")

    case value do
      0 -> assert offset >= 0
      v -> assert offset == v
    end
  end

  defp assert_tus_max_size(conn) do
    max_size = get_tus_max_size() |> to_string()
    assert max_size == get_header(conn, "tus-max-size")
  end

  defp assert_upload_expires(conn) do
    assert expires = get_header(conn, "upload-expires")
    assert Timex.parse!(expires, "{WDshort}, {0D} {Mshort} {YYYY} {h24}:{m}:{s} GMT")
  end

  defp get_tus_max_size do
    :tus_plug
    |> Application.get_env(TusPlug)
    |> Keyword.get(:max_size)
  end

  defp get_header(conn, header) do
    conn
    |> get_resp_header(header)
    |> case do
      [value] -> value
      _ -> nil
    end
  end

  defp upload_baseurl do
    TusPlug.upload_baseurl()
  end

  defp tmp_file(filename) do
    Application.get_env(:tus_plug, TusPlug)
    |> Keyword.get(:upload_path)
    |> Path.join(filename)
  end

  defp upload_chunk(filename, data, offset) do
    newconn =
      conn(:patch, "#{upload_baseurl()}/#{filename}", data)
      |> put_req_header("upload-offset", offset)
      |> put_req_header("tus-resumable", "1.0.0")
      |> put_req_header("content-type", "application/offset+octet-stream")

    opts = TusPlug.init([])
    newconn = newconn |> TusPlug.call(opts)

    res = sent_resp(newconn)
    {:ok, newconn, res}
  end

  defp gen_metadata do
    [{"foo", "bar"}, {"bar", "baz"}]
    |> Enum.map(fn {key, value} ->
      b64value = Base.encode64(value)
      "#{key} #{b64value}"
    end)
    |> Enum.join(",")
  end

  defp empty_file_fixture(filename, size \\ 42) do
    # fixture
    # create an entry into the cache
    alias TusPlug.Cache
    alias TusPlug.Cache.Entry
    filename |> tmp_file() |> File.touch!()

    {res, _} =
      %Entry{id: filename, filename: filename, started_at: DateTime.utc_now(), size: size}
      |> Cache.put()

    res
  end
end
