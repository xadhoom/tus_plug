defmodule Tus.Plug do
  @moduledoc """
  Plug implementation for the tus.io protocol
  """
  import Plug.Conn

  alias Tus.Plug.{HEAD, PATCH}

  def init(_opts) do
    %{
      upload_path: upload_path(),
      upload_baseurl: upload_baseurl()
    }
  end

  def call(%{method: "OPTIONS"} = conn, opts) do
    with {:ok, conn} <- check_path(conn, opts) do
      conn
      |> put_resp_header("tus-version", version())
      |> resp(:no_content, "")
    else
      {:error, :nomatch} ->
        conn
    end
    |> do_response()
  end

  def call(%{method: "HEAD"} = conn, opts) do
    with {:ok, conn} <- check_path(conn, opts),
         {:ok, conn} <- preconditions(conn, opts),
         {:ok, conn} <- extract_filename(conn, opts) do
      conn
      |> HEAD.call(opts)
    else
      {:error, :nomatch} ->
        conn

      {:error, :nofile} ->
        conn
        |> resp(:bad_request, "")

      {:error, :precondition} ->
        conn |> resp(:precondition_failed, "")
    end
    |> do_response()
  end

  def call(%{method: "PATCH"} = conn, opts) do
    with {:ok, conn} <- check_path(conn, opts),
         {:ok, conn} <- preconditions(conn, opts),
         {:ok, conn} <- extract_filename(conn, opts) do
      conn
      |> PATCH.call(opts)
    else
      {:error, :nomatch} ->
        conn

      {:error, :nofile} ->
        conn
        |> resp(:bad_request, "")

      {:error, :precondition} ->
        conn |> resp(:precondition_failed, "")
    end
    |> do_response()
  end

  def call(conn, _) do
    conn
  end

  @doc false
  def upload_path() do
    :tus
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:upload_path, "/tmp")
  end

  @doc false
  def upload_baseurl() do
    :tus
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:upload_baseurl)
  end

  @doc false
  def version() do
    :tus
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:version, "1.0.0")
  end

  defp do_response(%{state: :set} = conn) do
    conn
    |> put_resp_header("tus-resumable", version())
    |> put_resp_header("tus-version", version())
    |> halt()
    |> send_resp()
  end

  defp do_response(conn) do
    conn
  end

  defp preconditions(conn, _opts) do
    myversion = version()

    conn
    |> get_req_header("tus-resumable")
    |> case do
      [^myversion] ->
        {:ok, conn}

      _ ->
        {:error, :precondition}
    end
  end

  defp check_path(conn, opts) do
    path_info = basepath(conn.path_info)

    baseurl =
      ["" | path_info]
      |> Enum.join("/")

    case opts.upload_baseurl do
      ^baseurl ->
        {:ok, conn}

      _ ->
        {:error, :nomatch}
    end
  end

  defp extract_filename(conn, _opts) do
    conn.path_info
    |> filename()
    |> case do
      nil ->
        {:error, :nofile}

      filen ->
        {:ok,
         conn
         |> put_private(:filename, filen)}
    end
  end

  defp basepath([]) do
    []
  end

  defp basepath([path_info]), do: [path_info]

  defp basepath(path_info) do
    path_info
    |> Enum.take(Enum.count(path_info) - 1)
  end

  defp filename([]) do
    nil
  end

  defp filename([filename]) when is_binary(filename), do: filename

  defp filename(path_info) when is_list(path_info) do
    path_info
    |> Enum.take(-1)
    |> filename()
  end
end
