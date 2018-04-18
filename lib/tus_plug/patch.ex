defmodule TusPlug.PATCH do
  @moduledoc false
  import Plug.Conn

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

      {:error, :gone} ->
        conn |> resp(:gone, "")

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
  end

  defp write_data({:ok, data, conn}, {_, _offset, fd, opts, entry}) do
    :ok = IO.binwrite(fd, data)
    File.close(fd)

    path =
      conn.private[:filename]
      |> filepath(opts)

    new_offset = path |> File.stat!() |> Map.get(:size)

    {:ok, new_entry} = Cache.update(%{entry | offset: new_offset})

    conn
    |> put_resp_header("upload-offset", to_string(new_offset))
    |> TusPlug.add_expires_hdr(new_entry.expires_at)
    |> resp(:no_content, "")
  end

  defp write_data({:more, data, conn}, {_, offset, fd, opts, entry}) do
    :ok = IO.binwrite(fd, data)

    conn
    |> read_body(length: @max_body_read, read_length: @body_read_len)
    |> write_data({conn, offset, fd, opts, entry})
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

  defp check_offset(path, offset, %Entry{offset: stored_offset}) do
    case File.stat(path) do
      {:ok, %{size: ^offset}} ->
        case stored_offset do
          ^offset -> :ok
          _ -> {:error, :internal_offset_conflict}
        end

      {:ok, _} ->
        {:error, :offset_conflict}

      {:error, :enoent} ->
        {:error, :gone}
    end
  end
end
