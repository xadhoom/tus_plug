defmodule TusPlug.UrlHelper do
  @moduledoc false

  @nofile ["POST", "OPTIONS"]
  @withfile ["HEAD", "PATCH"]

  @doc false
  def validate(conn, opts) do
    case is_relative?(opts.upload_baseurl) do
      true -> validate_relative(conn, opts)
      false -> validate_absolute(conn, opts)
    end
  end

  defp validate_absolute(%{method: method} = conn, opts)
       when method in @nofile do
    upload_baseurl = opts.upload_baseurl

    case request_path(conn) do
      ^upload_baseurl -> {:ok, request_path(conn)}
      _ -> {:error, :nomatch}
    end
  end

  defp validate_absolute(%{method: method} = conn, opts)
       when method in @withfile do
    upload_baseurl = opts.upload_baseurl

    case base_path_with_file(conn) do
      {:ok, ^upload_baseurl, _} = res -> res
      _ -> {:error, :nomatch}
    end
  end

  defp validate_relative(%{method: method} = conn, opts)
       when method in @nofile do
    upload_baseurl = opts.upload_baseurl

    case last_matches?(conn, upload_baseurl) do
      true -> {:ok, request_path(conn)}
      _ -> {:error, :nomatch}
    end
  end

  defp validate_relative(%{method: method, path_info: path_info} = conn, opts)
       when method in @withfile do
    upload_baseurl = opts.upload_baseurl

    partial_path = path_info |> Enum.take(length(path_info) - 1)

    case last_matches?(%{path_info: partial_path}, upload_baseurl) do
      true ->
        {:ok, request_path(%{path_info: partial_path}), request_path(conn)}

      _ ->
        {:error, :nomatch}
    end
  end

  defp last_matches?(%{path_info: nil}, _segment), do: false

  defp last_matches?(%{path_info: []}, _segment), do: false

  defp last_matches?(%{path_info: path}, segment) do
    case Enum.at(path, -1) do
      ^segment -> true
      _ -> false
    end
  end

  defp request_path(conn) do
    # conn.request path may contain double slashes... /foo//bar/wat
    path = conn.path_info |> Enum.join("/")
    "/#{path}"
  end

  defp base_path_with_file(%{path_info: []}), do: {:error, :not_found}

  defp base_path_with_file(%{path_info: [single]}), do: {:ok, "/", "/#{single}"}

  defp base_path_with_file(%{path_info: path}) do
    base = path |> Enum.take(length(path) - 1) |> Enum.join("/")
    full = path |> Enum.join("/")

    {:ok, "/#{base}", "/#{full}"}
  end

  defp is_relative?(path) do
    !String.starts_with?(path, "/")
  end
end
