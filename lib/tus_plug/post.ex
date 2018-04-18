defmodule TusPlug.POST do
  @moduledoc false
  import Plug.Conn

  alias TusPlug.Cache
  alias TusPlug.Cache.Entry

  def call(%{method: "POST"} = conn, opts) do
    with {:ok, upload_len} <- get_upload_len(conn),
         :ok <- check_upload_len(upload_len),
         {:ok, location, entry} <- create(conn, opts) do
      conn
      |> put_resp_header("location", location)
      |> TusPlug.add_expires_hdr(entry.expires_at)
      |> resp(:created, "")
    else
      {:error, :max_size} ->
        conn |> resp(:request_entity_too_large, "")

      {:error, :upload_len} ->
        conn |> resp(:precondition_failed, "missing upload len")

      {:error, :metadata} ->
        conn |> resp(:precondition_failed, "metadata")
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

    case get_metadata(conn) do
      {:ok, md} ->
        {:ok, entry} =
          %Entry{
            id: fileid,
            filename: path,
            size: get_upload_len(conn),
            started_at: DateTime.utc_now(),
            metadata: md
          }
          |> Cache.put()

        {:ok, location, entry}

      {:error, :metadata} = err ->
        err
    end
  end

  defp filepath(filename, opts) do
    Path.join(opts.upload_path, filename)
  end

  defp get_metadata(conn) do
    md =
      conn
      |> get_req_header("upload-metadata")
      |> parse_metadata_hdr()

    case validate_metadata(md) do
      {:ok, md} -> {:ok, md}
      {:error, :metadata} -> {:error, :metadata}
    end
  end

  @doc false
  def validate_metadata(nil), do: {:ok, nil}

  @doc false
  def validate_metadata(""), do: {:ok, nil}

  @doc false
  def validate_metadata(metadata) when is_binary(metadata) do
    split =
      metadata
      |> String.trim()
      |> String.split(",")
      |> Enum.map(fn kv -> kv |> String.trim() end)

    split
    |> Enum.all?(fn kv ->
      kv =~ ~r/^[a-z|A-Z|0-9]+ [a-z|A-Z|0-9|=|\/|\+]+$/
    end)
    |> case do
      false ->
        {:error, :metadata}

      true ->
        md =
          split
          |> Enum.map(fn kv ->
            kv
            |> String.split(" ")
            |> List.to_tuple()
          end)

        {:ok, md}
    end
  end

  defp check_upload_len(len) when is_integer(len) do
    hard_len =
      :tus_plug
      |> Application.get_env(TusPlug, [])
      |> Keyword.get(:max_size, 4_294_967_296)

    case len do
      v when v > hard_len -> {:error, :max_size}
      _ -> :ok
    end
  end

  defp parse_metadata_hdr([]), do: nil

  defp parse_metadata_hdr([v]) when is_binary(v), do: v

  defp get_upload_len(conn) do
    conn
    |> get_req_header("upload-length")
    |> parse_upload_len()
  end

  defp parse_upload_len([]), do: {:error, :upload_len}

  defp parse_upload_len([v]), do: parse_upload_len(v)

  defp parse_upload_len(v) when is_binary(v) do
    v
    |> String.to_integer()
    |> parse_upload_len()
  end

  defp parse_upload_len(v) when is_integer(v) and v >= 0, do: {:ok, v}

  defp parse_upload_len(_), do: {:error, :upload_len}

  defp gen_filename do
    Base.hex_encode32(:crypto.strong_rand_bytes(20), case: :lower)
  end
end
