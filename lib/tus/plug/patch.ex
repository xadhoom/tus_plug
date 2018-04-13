defmodule Tus.Plug.PATCH do
  @moduledoc false
  import Plug.Conn

  def call(%{method: "PATCH"} = conn, opts) do
    path =
      conn.private[:filename]
      |> filepath(opts)

    with {:ok, offset} <- get_offset(conn),
         :ok <- check_offset(path, offset),
         {:ok, fd} <- File.open(path, [:append]) do
      conn
      |> read_body()
      |> write_data({conn, offset, fd, opts})
    else
      {:error, :offset} ->
        conn |> resp(:precondition_failed, "")

      {:error, :gone} ->
        conn |> resp(:gone, "")

      {:error, :offset_conflict} ->
        conn |> resp(:conflict, "")

      {:error, _} ->
        conn
        |> resp(:internal_server_error, "")
    end
  end

  defp write_data({:ok, data, conn}, {_, offset, fd, opts}) do
    :ok = IO.binwrite(fd, data)
    File.close(fd)

    path =
      conn.private[:filename]
      |> filepath(opts)

    new_offset = File.stat!(path) |> Map.get(:size)

    conn
    |> put_resp_header("upload-offset", new_offset)
    |> resp(:no_content, "")
  end

  defp write_data({:more, data, conn}, {_, offset, fd, opts}) do
    :ok = IO.binwrite(fd, data)

    conn
    |> read_body()
    |> write_data({conn, offset, fd, opts})
  end

  defp write_data({:error, _err}, {conn, _, _, _}) do
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
    String.to_integer(v)
    |> parse_offset()
  end

  defp parse_offset(v) when is_integer(v) and v >= 0, do: {:ok, v}

  defp parse_offset(_), do: {:error, :offset}

  defp filepath(filename, opts) do
    Path.join(opts.upload_path, filename)
  end

  defp check_offset(path, 0) do
    :ok
  end

  defp check_offset(path, offset) do
    case File.stat(path) do
      {:ok, %{size: ^offset}} -> :ok
      {:ok, _} -> {:error, :offset_conflict}
      {:error, :enoent} -> {:error, :gone}
    end
  end
end
