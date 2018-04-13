defmodule Tus.Plug.HEAD do
  @moduledoc false
  import Plug.Conn

  def call(%{method: "HEAD"} = conn, opts) do
    #
    path =
      conn.private[:filename]
      |> filepath(opts)

    case File.stat(path) do
      {:error, _} ->
        conn
        |> resp(:not_found, "")

      {:ok, %{size: size, type: :regular}} ->
        conn
        |> put_resp_header("upload-offset", to_string(size))
        |> resp(:ok, "")

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
end
