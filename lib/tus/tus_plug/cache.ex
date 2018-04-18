defmodule TusPlug.Cache.Entry do
  @moduledoc """
  Structure rapresenting an Entry into the upload cache
  """
  defstruct id: nil,
            filename: nil,
            offset: 0,
            size: 0,
            started_at: nil,
            metadata: nil
end

defmodule TusPlug.Cache do
  @moduledoc false
  use GenServer

  alias TusPlug.Cache.Entry

  @table_fname "tus_cache.tab"

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def put(%Entry{} = entry) do
    GenServer.call(__MODULE__, {:put, entry})
  end

  def get(file_id) do
    GenServer.call(__MODULE__, {:get, file_id})
  end

  def init(_) do
    state = %{
      cache: init_cache()
    }

    {:ok, state}
  end

  def handle_call({:get, file_id}, _from, state) do
    res =
      case :ets.lookup(state.cache, file_id) do
        [] -> {:error, :not_found}
        [{_k, entry}] -> {:ok, entry}
      end

    {:reply, res, state}
  end

  def handle_call({:put, %{id: nil}}, _from, state) do
    {:reply, {:error, :id}, state}
  end

  def handle_call({:put, %{filename: nil}}, _from, state) do
    {:reply, {:error, :filename}, state}
  end

  def handle_call({:put, %{size: 0}}, _from, state) do
    {:reply, {:error, :size}, state}
  end

  def handle_call({:put, %{id: id} = entry}, _from, state) do
    :ets.insert(state.cache, {id, entry})
    {:reply, :ok, state}
  end

  defp cache_path do
    Application.get_env(:tus_plug, __MODULE__, [])
    |> Keyword.get(:persistence_path, "/tmp")
    |> Path.join(@table_fname)
  end

  defp init_cache do
    Application.get_env(:tus_plug, __MODULE__, [])
    |> Keyword.get(:ets_backend, PersistentEts)
    |> case do
      :ets -> :ets.new(__MODULE__, [])
      PersistentEts -> PersistentEts.new(__MODULE__, "#{cache_path()}", [])
    end
  end
end
