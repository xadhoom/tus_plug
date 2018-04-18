defmodule TusPlug.Test.TusPlug.PostTest do
  @moduledoc false
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias TusPlug.POST

  property "valid metadata" do
    check all metadata <- kv_generator() do
      res = POST.validate_metadata(metadata)
      assert check_metadata(res)
    end
  end

  defp kv_generator do
    bind(list_of(build_kv()), fn list ->
      res = Enum.join(list, ",")
      constant(res)
    end)
  end

  defp build_kv do
    bind(string(:alphanumeric, min_length: 1), fn key ->
      bind(binary(min_length: 1), fn value ->
        value = Base.encode64(value)
        constant("#{key} #{value}")
      end)
    end)
  end

  defp check_metadata({:ok, nil}) do
    true
  end

  defp check_metadata({:ok, md}) when is_list(md) do
    md
    |> Enum.all?(fn
      {_k, _v} -> true
      _ -> false
    end)
  end

  defp check_metadata(_) do
    false
  end
end
