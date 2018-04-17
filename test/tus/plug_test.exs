defmodule Tus.Test.PlugTest do
  @moduledoc false
  use ExUnit.Case, async: true

  use Plug.Test

  alias Tus.Plug, as: TusPlug

  test "not matching path just returns conn" do
    c = conn(:get, "/foo/var")
    conn = TusPlug.call(c, TusPlug.init([]))

    assert conn == c
  end

  describe "HEAD" do
    test "happy path" do
      newconn =
        conn(:head, "#{upload_baseurl()}/stuff.gz")
        |> put_req_header("tus-resumable", "1.0.0")

      opts = TusPlug.init([])
      newconn = newconn |> TusPlug.call(opts)

      assert {200, _headers, _body} = sent_resp(newconn)

      assert_upload_offset(newconn)
      assert_cache_control(newconn)
      assert_tus_resumable(newconn)
    end

    test "file not found" do
      assert false
    end
  end

  describe "PATCH" do
    test "happy path" do
      # fixture
      filename = "patch.random"
      tmp_file(filename) |> File.touch!()

      body = "yadda"

      newconn =
        conn(:patch, "#{upload_baseurl()}/#{filename}", body)
        |> put_req_header("upload-offset", "0")
        |> put_req_header("tus-resumable", "1.0.0")
        |> put_req_header("content-tye", "application/offset+octet-stream")

      opts = TusPlug.init([])
      newconn = newconn |> TusPlug.call(opts)

      assert {204, _headers, _body} = sent_resp(newconn)

      assert_upload_offset(newconn, byte_size(body) |> to_string())
      assert_tus_resumable(newconn)

      tmp_file(filename) |> File.rm!()
    end

    test "multiple requests" do
      # fixture
      filename = "patch.random"
      tmp_file(filename) |> File.touch!()

      # first segment
      body = "yadda"

      {:ok, _, res} = upload_chunk(filename, body, "0")
      assert {204, _headers, _body} = res

      # 2nd segment
      body2 = "baz"

      {:ok, newconn2, res} = upload_chunk(filename, body2, "5")
      assert {204, _headers, _body} = res

      # checks
      assert_upload_offset(newconn2, byte_size(body <> body2) |> to_string())
      assert_tus_resumable(newconn2)
      assert body <> body2 == File.read!(tmp_file(filename))

      tmp_file(filename) |> File.rm!()
    end

    test "file does not exists" do
      newconn =
        conn(:patch, "#{upload_baseurl()}/notfound", "body")
        |> put_req_header("upload-offset", "0")
        |> put_req_header("tus-resumable", "1.0.0")
        |> put_req_header("content-tye", "application/offset+octet-stream")

      opts = TusPlug.init([])
      newconn = newconn |> TusPlug.call(opts)

      assert {404, _headers, _body} = sent_resp(newconn)
    end

    test "conflict" do
      # fixture
      filename = "patch.conflict"
      tmp_file(filename) |> File.touch!()

      {:ok, _, _} = upload_chunk(filename, "somedata", "0")

      # overlapping
      {:ok, _, res} = upload_chunk(filename, "dataother", "5")

      # assert conflict
      assert {409, _headers, _body} = res

      tmp_file(filename) |> File.rm!()
    end
  end

  describe "POST" do
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
    end
  end

  def assert_tus_extensions(conn) do
    assert "creation" = get_header(conn, "tus-extension")
  end

  defp assert_cache_control(conn) do
    assert "no-store" = get_header(conn, "cache-control")
  end

  defp assert_tus_resumable(conn) do
    version = Application.get_env(:tus, :version, "1.0.0")
    assert version == get_header(conn, "tus-resumable")
  end

  defp assert_tus_version(conn) do
    version = Application.get_env(:tus, :version, "1.0.0")
    assert version == get_header(conn, "tus-version")
  end

  defp assert_upload_offset(conn, value \\ 0) do
    assert offset = get_header(conn, "upload-offset")

    case value do
      0 -> assert offset >= 0
      v -> assert offset == v
    end
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
    Application.get_env(:tus, Tus.Plug)
    |> Keyword.get(:upload_path)
    |> Path.join(filename)
  end

  def upload_chunk(filename, data, offset) do
    newconn =
      conn(:patch, "#{upload_baseurl()}/#{filename}", data)
      |> put_req_header("upload-offset", offset)
      |> put_req_header("tus-resumable", "1.0.0")
      |> put_req_header("content-tye", "application/offset+octet-stream")

    opts = TusPlug.init([])
    newconn = newconn |> TusPlug.call(opts)

    res = sent_resp(newconn)
    {:ok, newconn, res}
  end
end
