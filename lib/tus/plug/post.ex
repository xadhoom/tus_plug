defmodule Tus.Plug.POST do
  @moduledoc false
  import Plug.Conn

  alias Tus.Plug.Cache
  alias Tus.Plug.Cache.Entry

  def call(%{method: "POST"} = conn, opts) do
    with {:ok, _upload_len} <- get_upload_len(conn),
         {:ok, location} <- create(conn, opts) do
      conn
      |> put_resp_header("location", location)
      |> resp(:created, "")
    else
      {:error, :upload_len} ->
        conn |> resp(:precondition_failed, "")
    end
  end

  defp create(conn, opts) do
    fileid = gen_filename()
    path = filepath(fileid, opts)
    :ok = File.touch!(path)

    location =
      "#{conn.scheme}://#{conn.host}:#{conn.port}"
      |> URI.merge(Path.join(opts.upload_baseurl, fileid))
      |> to_string

    :ok =
      %Entry{id: fileid, filename: path, size: get_upload_len(conn), metadata: get_metadata(conn)}
      |> Cache.put()

    {:ok, location}
  end

  defp filepath(filename, opts) do
    Path.join(opts.upload_path, filename)
  end

  defp get_metadata(conn) do
    conn
    |> get_req_header("upload-metadata")
    |> parse_metadata()
  end

  defp parse_metadata([]), do: nil

  defp parse_metadata([v]) when is_binary(v), do: v

  defp get_upload_len(conn) do
    conn
    |> get_req_header("upload-length")
    |> parse_upload_len()
  end

  defp parse_upload_len([]), do: {:error, :upload_len}

  defp parse_upload_len([v]), do: parse_upload_len(v)

  defp parse_upload_len(v) when is_binary(v) do
    String.to_integer(v)
    |> parse_upload_len()
  end

  defp parse_upload_len(v) when is_integer(v) and v >= 0, do: {:ok, v}

  defp parse_upload_len(_), do: {:error, :upload_len}

  defp gen_filename do
    Base.hex_encode32(:crypto.strong_rand_bytes(20), case: :lower)
  end
end
