defmodule TusPlug.PATCH do
  @moduledoc false
  import Plug.Conn

  alias TusPlug.Upload
  alias TusPlug.Cache
  alias TusPlug.Cache.Entry

  @max_body_read Application.get_env(:tus_plug, TusPlug)
                 |> Keyword.get(:max_body_read)
  @body_read_len Application.get_env(:tus_plug, TusPlug)
                 |> Keyword.get(:body_read_len)

  def call(%{method: "PATCH"} = conn, opts) do
    filename = conn.private[:filename]
    path = filepath(filename, opts)

    with {:ok, offset} <- get_offset(conn),
         {:ok, %Entry{} = entry} <- Cache.get(filename),
         :ok <- check_offset(path, offset, entry),
         {:ok, _} <- File.stat(path),
         {:ok, fd} <- File.open(path, [:append]) do
      conn
      |> read_body(length: @max_body_read, read_length: @body_read_len)
      |> write_data({conn, offset, fd, opts, entry})
    else
      {:error, :offset} ->
        conn |> resp(:precondition_failed, "")

      {:error, :internal_offset_conflict} ->
        conn |> resp(:internal_server_error, "")

      {:error, :offset_conflict} ->
        conn |> resp(:conflict, "")

      {:error, :enoent} ->
        conn |> resp(:not_found, "")

      {:error, :not_found} ->
        conn |> resp(:not_found, "")

      {:error, _} ->
        conn
        |> resp(:internal_server_error, "")
    end
    |> halt_if_not_completed()
  end

  defp write_data({:ok, data, conn}, {_, _offset, fd, opts, entry}) do
    if byte_size(data) + entry.offset > entry.size do
      conn
      |> resp(:request_entity_too_large, "Size exceeded")
    else
      case append_data(fd, data, true) do
        :ok ->
          {:ok, new_entry} =
            Cache.update(%{entry | offset: entry.offset + byte_size(data)})

          conn
          |> check_completed_upload(new_entry, opts)
          |> put_resp_header("upload-offset", to_string(new_entry.offset))
          |> TusPlug.add_expires_hdr(new_entry.expires_at)
          |> resp(:no_content, "")

        _ ->
          Cache.delete(entry)

          conn
          |> resp(:internal_server_error, "write or close error")
      end
    end
  end

  defp write_data({:more, data, conn}, {_, offset, fd, opts, entry}) do
    if byte_size(data) + entry.offset > entry.size do
      conn
      |> resp(:request_entity_too_large, "Size exceeded")
    else
      case append_data(fd, data, false) do
        :ok ->
          newentry = %{entry | offset: entry.offset + byte_size(data)}

          conn
          |> read_body(length: @max_body_read, read_length: @body_read_len)
          |> write_data({conn, offset, fd, opts, newentry})

        _ ->
          Cache.delete(entry)

          conn
          |> resp(:internal_server_error, "write error")
      end
    end
  end

  defp write_data({:error, _err}, {conn, _, _, _, _}) do
    conn
    |> resp(:internal_server_error, "")
  end

  defp get_offset(conn) do
    conn
    |> get_req_header("upload-offset")
    |> parse_offset()
  end

  defp parse_offset([]), do: {:error, :offset}

  defp parse_offset([v]), do: parse_offset(v)

  defp parse_offset(v) when is_binary(v) do
    v
    |> String.to_integer()
    |> parse_offset()
  end

  defp parse_offset(v) when is_integer(v) and v >= 0, do: {:ok, v}

  defp parse_offset(_), do: {:error, :offset}

  defp filepath(filename, opts) do
    Path.join(opts.upload_path, filename)
  end

  defp check_offset(path, offset, %Entry{offset: stored_offset} = entry) do
    case File.stat(path) do
      {:ok, %{size: ^offset}} ->
        case stored_offset do
          ^offset -> :ok
          _ -> {:error, :internal_offset_conflict}
        end

      {:ok, _} ->
        {:error, :offset_conflict}

      {:error, :enoent} ->
        Cache.delete(entry)
        {:error, :not_found}
    end
  end

  defp append_data(fd, data, false) do
    case IO.binwrite(fd, data) do
      :ok -> :ok
      {:error, _} -> {:error, :write}
    end
  end

  defp append_data(fd, data, true) do
    with :ok <- IO.binwrite(fd, data),
         :ok <- File.close(fd) do
      :ok
    else
      {:error, _} -> {:error, :write}
    end
  end

  defp check_completed_upload(conn, entry, opts) do
    offset = entry.offset

    case entry.size do
      ^offset ->
        Cache.delete(entry)

        conn
        |> add_upload_info(entry, opts)

      _ ->
        conn
    end
  end

  defp add_upload_info(conn, entry, opts) do
    path = conn.private[:filename] |> filepath(opts)

    info = %Upload{
      filename: entry.filename,
      path: path,
      metadata: entry.metadata
    }

    conn
    |> put_private(TusPlug.Upload, info)
    |> put_private(TusPlug.Upload.Completed, true)
  end

  defp halt_if_not_completed(conn) do
    case conn.private[TusPlug.Upload.Completed] do
      true -> conn
      _ -> conn |> halt()
    end
  end
end
