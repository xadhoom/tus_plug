defmodule TusPlug.Upload do
  @moduledoc """
  Holds details of a completed upload
  """
  @type t :: %{
          filename: binary(),
          path: binary(),
          metadata: map()
        }

  @enforce_keys [:filename, :path]
  defstruct filename: nil, path: nil, metadata: nil
end

defmodule TusPlug do
  @moduledoc """
  Plug implementation for the tus.io protocol
  """
  import Plug.Conn

  alias TusPlug.{HEAD, PATCH, POST, Config}

  @methods ["OPTIONS", "HEAD", "PATCH", "POST"]

  def init(opts) when is_list(opts) do
    opts_map = Map.new(opts)

    %Config{}
    |> Map.merge(opts_map)
  end

  def call(%{method: meth} = conn, opts) when meth in @methods do
    case get_req_header(conn, "x-http-method-override") do
      [] ->
        call_impl(conn, opts)

      [wants_method] when wants_method in @methods ->
        call_impl(%{conn | method: wants_method}, opts)
    end
  end

  def call(conn, _) do
    conn
  end

  defp call_impl(%{method: "OPTIONS"} = conn, opts) do
    with {:ok, conn} <- check_path(conn, opts) do
      conn
      |> add_version_h(opts)
      |> add_extensions_h()
      |> resp(:no_content, "")
    else
      {:error, :nomatch} ->
        conn
    end
    |> halt()
    |> do_response(opts)
  end

  defp call_impl(%{method: "HEAD"} = conn, opts) do
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
    |> halt()
    |> do_response(opts)
  end

  defp call_impl(%{method: "PATCH"} = conn, opts) do
    with :ok <- check_content_type(conn),
         {:ok, conn} <- check_path(conn, opts),
         {:ok, conn} <- preconditions(conn, opts),
         {:ok, conn} <- extract_filename(conn, opts) do
      conn
      |> PATCH.call(opts)
    else
      {:error, :content_type} ->
        conn
        |> resp(:bad_request, "")

      {:error, :nomatch} ->
        conn

      {:error, :nofile} ->
        conn
        |> resp(:bad_request, "")

      {:error, :precondition} ->
        conn |> resp(:precondition_failed, "")
    end
    |> do_response(opts)
  end

  defp call_impl(%{method: "POST"} = conn, opts) do
    with {:ok, conn} <- check_path(conn, opts),
         {:ok, conn} <- preconditions(conn, opts),
         {:error, _} <- extract_filename(conn, opts) do
      conn
      |> POST.call(opts)
    else
      {:error, :nomatch} ->
        conn

      {:ok, _} ->
        conn |> resp(:not_found, "")

      {:error, :precondition} ->
        conn |> resp(:precondition_failed, "")
    end
    |> halt()
    |> do_response(opts)
  end

  @doc false
  def version(opts) do
    opts.version
  end

  @doc false
  def add_expires_hdr(conn, %DateTime{} = dt) do
    {:ok, expires} =
      dt
      |> Timex.format("{WDshort}, {0D} {Mshort} {YYYY} {h24}:{m}:{s} GMT")

    conn
    |> put_resp_header("upload-expires", expires)
  end

  defp do_response(%{state: :set} = conn, opts) do
    conn
    |> put_resp_header("tus-resumable", version(opts))
    |> add_version_h(opts)
    |> add_extensions_h()
    |> add_max_size_h(opts)
    |> send_resp()
  end

  defp do_response(conn, _opts) do
    conn
  end

  defp preconditions(conn, opts) do
    myversion = version(opts)

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
    baseurl = conn.path_info |> basepath() |> Enum.join()

    conn.path_info
    |> filename()
    |> case do
      nil ->
        {:error, :nofile}

      ^baseurl ->
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

  defp add_version_h(conn, opts) do
    conn
    |> put_resp_header("tus-version", version(opts))
  end

  defp add_extensions_h(conn) do
    conn
    |> put_resp_header("tus-extension", extensions())
  end

  defp add_max_size_h(conn, opts) do
    conn
    |> put_resp_header("tus-max-size", to_string(opts.max_size))
  end

  defp extensions do
    "creation,expiration"
  end

  defp check_content_type(conn) do
    # checks for application/offset+octet-stream
    conn
    |> get_req_header("content-type")
    |> case do
      ["application/offset+octet-stream"] -> :ok
      _ -> {:error, :content_type}
    end
  end
end
