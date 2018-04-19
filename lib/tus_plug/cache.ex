defmodule TusPlug.Cache.Entry do
  @moduledoc """
  Structure rapresenting an Entry into the upload cache
  """
  defstruct id: nil,
            filename: nil,
            offset: 0,
            size: 0,
            started_at: nil,
            expires_at: nil,
            metadata: nil
end

defmodule TusPlug.Cache do
  @moduledoc false
  use GenServer

  alias Timex.Duration
  alias TusPlug.Cache.Entry

  require Logger

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

  def update(%Entry{} = entry) do
    GenServer.call(__MODULE__, {:update, entry})
  end

  def delete(%Entry{} = entry) do
    GenServer.cast(__MODULE__, {:delete, entry})
  end

  def init(_) do
    state = %{
      cache: init_cache()
    }

    Process.send_after(self(), {:expire_timer, new_expire()}, get_entry_ttl())

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
    ttl = Duration.from_milliseconds(get_entry_ttl())
    expires_at = Timex.add(entry.started_at, ttl)

    newentry = %{entry | expires_at: expires_at}
    :ets.insert(state.cache, {id, newentry})

    {:reply, {:ok, newentry}, state}
  end

  def handle_call({:update, %{id: id} = entry}, _from, state) do
    ttl = Duration.from_milliseconds(get_entry_ttl())
    expires_at = Timex.add(entry.expires_at, ttl)

    :ets.insert(state.cache, {id, %{entry | expires_at: expires_at}})
    {:reply, {:ok, entry}, state}
  end

  def handle_cast({:delete, %{id: id}}, state) do
    :ets.delete(state.cache, id)
    {:noreply, state}
  end

  def handle_info({:expire_timer, now}, state) do
    :ok = expire_entries(state, now)

    Process.send_after(self(), {:expire_timer, new_expire()}, get_entry_ttl())
    {:noreply, state}
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

  defp get_entry_ttl do
    :tus_plug
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:ttl, 5000)
  end

  defp expire_entries(state, now) do
    :ets.tab2list(state.cache)
    |> Enum.filter(fn {_k, entry} ->
      now
      |> DateTime.diff(entry.expires_at, :microsecond)
      |> case do
        v when v > 0 -> true
        _ -> false
      end
    end)
    |> Enum.each(fn {k, entry} ->
      Logger.info(fn -> "Removing cache entry #{inspect(entry)}" end)
      file = Path.join(TusPlug.upload_path(), entry.filename)

      case File.rm(file) do
        :ok -> :ets.delete(state.cache, k)
        err -> Logger.error("Could not remove cache entry: #{inspect(err)}")
      end
    end)
  end

  defp new_expire do
    DateTime.utc_now()
    |> Timex.add(Duration.from_milliseconds(get_entry_ttl()))
  end
end
