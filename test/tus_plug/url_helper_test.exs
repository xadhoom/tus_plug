defmodule TusPlug.Test.TusPlug.UrlHelperTest do
  @moduledoc false
  use ExUnit.Case, async: true
  use ExUnitProperties
  use Plug.Test

  alias TusPlug.UrlHelper

  describe "Absolute baseurl" do
    property "POST valid url" do
      check all url <- abs_url() do
        c = conn(:post, url)

        res = UrlHelper.validate(c, %{upload_baseurl: url})

        assert {:ok, ^url} = res
      end
    end

    property "POST invalid url" do
      check all {base_url, file_url} <- abs_url_with_file() do
        c = conn(:post, file_url)

        res = UrlHelper.validate(c, %{upload_baseurl: base_url})

        assert {:error, :nomatch} = res
      end
    end

    property "OPTIONS valid url" do
      check all url <- abs_url() do
        c = conn(:options, url)

        res = UrlHelper.validate(c, %{upload_baseurl: url})

        assert {:ok, ^url} = res
      end
    end

    property "OPTIONS invalid url" do
      check all {base_url, file_url} <- abs_url_with_file() do
        c = conn(:options, file_url)

        res = UrlHelper.validate(c, %{upload_baseurl: base_url})

        assert {:error, :nomatch} = res
      end
    end

    property "HEAD valid url" do
      check all {base_url, file_url} <- abs_url_with_file() do
        c = conn(:head, file_url)

        res = UrlHelper.validate(c, %{upload_baseurl: base_url})

        assert {:ok, ^base_url, ^file_url} = res
      end
    end

    property "HEAD invalid url" do
      check all {base_url, file_url} <- abs_url_with_file() do
        c = conn(:head, file_url)
        res = UrlHelper.validate(c, %{upload_baseurl: file_url})
        assert {:error, :nomatch} = res

        c = conn(:head, base_url)
        res = UrlHelper.validate(c, %{upload_baseurl: base_url})
        assert {:error, :nomatch} = res
      end
    end

    property "PATCH valid url" do
      check all {base_url, file_url} <- abs_url_with_file() do
        c = conn(:patch, file_url)

        res = UrlHelper.validate(c, %{upload_baseurl: base_url})

        assert {:ok, ^base_url, ^file_url} = res
      end
    end

    property "PATCH invalid url" do
      check all {base_url, file_url} <- abs_url_with_file() do
        c = conn(:patch, file_url)
        res = UrlHelper.validate(c, %{upload_baseurl: file_url})
        assert {:error, :nomatch} = res

        c = conn(:patch, base_url)
        res = UrlHelper.validate(c, %{upload_baseurl: base_url})
        assert {:error, :nomatch} = res
      end
    end
  end

  describe "Relative baseurl" do
    # when a relative path is specified, only the last
    # part must match for OPTIONS and POST, and last-1
    # for HEAD and PATCH (because last is the file)

    property "POST valid url" do
      relative = "files"

      check all url <- relative_url(relative) do
        c = conn(:post, url)
        res = UrlHelper.validate(c, %{upload_baseurl: relative})

        assert {:ok, ^url} = res
      end
    end

    property "POST invalid url" do
      check all url <- relative_url("foo") do
        c = conn(:post, url)
        res = UrlHelper.validate(c, %{upload_baseurl: "bar"})

        assert {:error, :nomatch} = res
      end
    end

    property "OPTIONS valid url" do
      relative = "files"

      check all url <- relative_url(relative) do
        c = conn(:options, url)
        res = UrlHelper.validate(c, %{upload_baseurl: relative})

        assert {:ok, ^url} = res
      end
    end

    property "OPTIONS invalid url" do
      check all url <- relative_url("foo") do
        c = conn(:options, url)
        res = UrlHelper.validate(c, %{upload_baseurl: "bar"})

        assert {:error, :nomatch} = res
      end
    end

    property "HEAD valid url" do
      relative = "files"

      check all {baseurl, fileurl} <- relative_url_with_file(relative) do
        c = conn(:head, fileurl)
        res = UrlHelper.validate(c, %{upload_baseurl: relative})

        assert {:ok, ^baseurl, ^fileurl} = res
      end
    end

    property "HEAD invalid url" do
      relative = "files"

      check all {_baseurl, fileurl} <- relative_url_with_file(relative) do
        c = conn(:head, fileurl)
        res = UrlHelper.validate(c, %{upload_baseurl: "foobar"})

        assert {:error, :nomatch} = res
      end
    end

    property "PATCH valid url" do
      relative = "files"

      check all {baseurl, fileurl} <- relative_url_with_file(relative) do
        c = conn(:patch, fileurl)
        res = UrlHelper.validate(c, %{upload_baseurl: relative})

        assert {:ok, ^baseurl, ^fileurl} = res
      end
    end

    property "PATCH invalid url" do
      relative = "files"

      check all {_baseurl, fileurl} <- relative_url_with_file(relative) do
        c = conn(:patch, fileurl)
        res = UrlHelper.validate(c, %{upload_baseurl: "foobar"})

        assert {:error, :nomatch} = res
      end
    end
  end

  defp abs_url_with_file do
    bind(list_of(path_segment(), min_length: 1), fn
      [file] ->
        constant({"/", "/#{file}"})

      list ->
        base_url = list |> Enum.take(length(list) - 1) |> Enum.join("/")
        file_url = Enum.join(list, "/")
        constant({"/#{base_url}", "/#{file_url}"})
    end)
  end

  defp abs_url do
    bind(list_of(path_segment()), fn
      [] ->
        constant("/")

      [single] ->
        constant("/#{single}")

      list ->
        res = Enum.join(list, "/")
        constant("/#{res}")
    end)
  end

  defp relative_url_with_file(last) do
    bind(list_of(path_segment(), min_length: 1), fn
      [file] ->
        constant({"/#{last}", "/#{last}/#{file}"})

      list ->
        base_url = list |> Enum.take(length(list) - 1) |> Enum.join("/")
        file = Enum.at(list, -1)
        constant({"/#{base_url}/#{last}", "/#{base_url}/#{last}/#{file}"})
    end)
  end

  defp relative_url(last) do
    bind(list_of(path_segment()), fn
      [] ->
        constant("/#{last}")

      [single] ->
        constant("/#{single}/#{last}")

      list ->
        res = Enum.join(list, "/")
        constant("/#{res}/#{last}")
    end)
  end

  defp path_segment do
    string(:alphanumeric, min_length: 1)
  end
end
