defmodule TusPlug.HEAD do
  @moduledoc false
  import Plug.Conn

  alias TusPlug.Cache
  alias TusPlug.Cache.Entry

  def call(%{method: "HEAD"} = conn, opts) do
    #
    filename = conn.private[:filename]
    path = filepath(filename, opts)

    with {:ok, %Entry{} = entry} <- Cache.get(filename),
         {:ok, %{size: size, type: :regular}} <- File.stat(path) do
      conn
      |> put_resp_header("upload-offset", to_string(size))
      |> put_metadata_hdr(entry)
      |> resp(:ok, "")
    else
      {:error, _} ->
        conn
        |> resp(:not_found, "")

      _ ->
        conn
        |> resp(:internal_server_error, "")
    end
    |> set_cache_control()
  end

  defp set_cache_control(conn) do
    conn
    |> put_resp_header("cache-control", "no-store")
  end

  defp filepath(filename, opts) do
    Path.join(opts.upload_path, filename)
  end

  defp put_metadata_hdr(conn, entry) do
    case encode_metadata(entry.metadata) do
      nil ->
        conn

      md ->
        conn
        |> put_resp_header("upload-metadata", md)
    end
  end

  defp encode_metadata(nil), do: nil

  defp encode_metadata(metadata) do
    metadata
    |> Enum.map(fn {k, v} ->
      "#{k} #{v}"
    end)
    |> Enum.join(",")
  end
end
