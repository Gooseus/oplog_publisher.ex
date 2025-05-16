defmodule OplogPublisher.Producer do
  use GenStage
  @behaviour Broadway.Producer
  alias Mongo
  require Logger

  @poll_interval 100

  @impl true
  def init(_opts) do
    Logger.info("Initializing producer...")

    with {:ok, mongo_url} <- fetch_mongo_url(),
         _ <- Logger.info("Connecting to MongoDB at #{mongo_url}..."),
         {:ok, conn} <- connect_to_mongo(mongo_url),
         _ <- Logger.info("Connected to MongoDB, setting up watch stream..."),
         {:ok, cursor} <- setup_watch_stream(conn) do
      # Start consuming the stream in a separate process
      send(self(), :process_stream)
      Logger.info("Watch stream setup complete")
      {:producer, %{cursor: cursor, demand: 0, cont: {:cont, []}}}
    else
      {:error, reason} ->
        Logger.error("Failed to initialize producer: #{inspect(reason, pretty: true)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_demand(incoming_demand, state) do
    # Don't just send a message, update the state and handle immediately
    Logger.info("Got demand: #{incoming_demand}")
    new_state = %{state | demand: state.demand + incoming_demand}
    handle_info(:process_stream, new_state)
  end

  @impl true
  def handle_info(:process_stream, %{cursor: cursor, demand: demand, cont: {:cont, []}} = state) do
    Logger.info("Processing stream with demand: #{demand}")
    case StreamStepper.next_item(cursor, {:cont, []}) do
      {:no_event, new_cont, stream} ->
        {:noreply, [], %{state | cont: new_cont, cursor: stream}}

      {item, new_cont, stream} ->
        # Save the resume token before wrapping the message
        if token = get_in(item, ["_id", "_data"]) do
          Logger.debug("Found resume token in message: #{token}")
          save_token(token)
        else
          Logger.warning("No resume token found in message")
        end
        {:noreply, [wrap_into_broadway_message(item)], %{state | cont: new_cont, cursor: stream}}
    end
  end

  def handle_info(:process_stream, %{cursor: cursor, demand: demand, cont: cont} = state)
      when demand > 0 do
    Logger.info("Processing stream with demand: #{demand}")
    Logger.info("cont: #{inspect(cont, pretty: true)}")

    try do
      {messages, continuation, cursor} = StreamStepper.take_n(cursor, cont, demand)
      base_state = %{state | cont: continuation, cursor: cursor}

      case messages do
        [] ->
          Process.send_after(self(), :process_stream, @poll_interval)
          {:noreply, [], base_state}

        messages ->
          messages = messages |> Enum.map(fn msg ->
            # Save the resume token from the _id._data field
            Logger.debug("Processing message: #{inspect(msg, pretty: true)}")
            if token = get_in(msg, ["_id", "_data"]) do
              Logger.debug("Found resume token in message: #{token}")
              save_token(token)
            else
              Logger.warning("No resume token found in message")
            end
            wrap_into_broadway_message(msg)
          end)
          remaining = demand - length(messages)
          new_state = %{base_state | demand: remaining}

          if remaining > 0 do
            send(self(), :process_stream)
            {:noreply, messages, new_state}
          else
            Process.send_after(self(), :process_stream, @poll_interval)
            {:noreply, messages, new_state}
          end
      end
    rescue
      e in Mongo.Error ->
        Logger.error("MongoDB error: #{inspect(e)}")
        handle_mongo_error(e, state)

      e ->
        Logger.error("Unexpected error in handle_info: #{Exception.format(:error, e, __STACKTRACE__)}")
        Process.send_after(self(), :process_stream, @poll_interval)
        {:noreply, [], state}
    end
  end

  def handle_info(:process_stream, state) do
    # No demand, just wait a bit
    Process.send_after(self(), :process_stream, @poll_interval)
    {:noreply, [], state}
  end

  # Private functions
  defp setup_watch_stream(conn) do
    try do
      pipeline = []

      options =
        case load_token() do
          nil -> [max_time: 1000, batch_size: 10]
          token -> [start_after: %{"_data" => token}, max_time: 1000, batch_size: 10]
        end

      Logger.debug("Setting up watch stream with options: #{inspect(options)}")
      cursor = Mongo.watch_collection(conn, "users", pipeline, nil, options)
      {:ok, cursor}
    rescue
      e ->
        Logger.error("Failed to setup watch stream: #{Exception.format(:error, e, __STACKTRACE__)}")
        {:error, e}
    end
  end

  defp wrap_into_broadway_message(data) do
    msg = %Broadway.Message{
      data: data,
      acknowledger: Broadway.NoopAcknowledger.init(),
      batch_key: :default,
      batcher: :default
    }

    Logger.debug("Created Broadway message: #{inspect(msg, pretty: true)}")
    msg
  end

  defp fetch_mongo_url do
    case Application.fetch_env(:oplog_publisher, :mongo_url) do
      {:ok, url} when is_binary(url) and url != "" -> {:ok, url}
      _ -> {:error, "MONGO_URI environment variable not set or invalid"}
    end
  end

  defp connect_to_mongo(url) do
    Mongo.start_link(
      url: url,
      pool_size: 2,
      set_name: "rs0",
      type: :replica_set_no_primary,
      socket_options: [
        nodelay: true,
        keepalive: true
      ],
      connect_timeout_ms: 60_000,
      server_selection_timeout_ms: 60_000,
      wait_queue_timeout_ms: 60_000
    )
  end

  @spec save_token(String.t()) :: :ok
  defp save_token(token_data) when is_binary(token_data) do
    Logger.debug("Saving resume token: #{token_data}")
    File.write!(".resume_token", :erlang.term_to_binary(token_data))
  end

  defp load_token do
    case File.read(".resume_token") do
      {:ok, bin} -> :erlang.binary_to_term(bin)
      _ -> nil
    end
  end

  @impl Broadway.Producer
  def prepare_for_start(_module, options) do
    {[], options}
  end

  defp handle_mongo_error(%Mongo.Error{code: 43} = _e, state) do
    Logger.warning("Cursor expired, recreating stream...")

    case setup_watch_stream(state.conn) do
      {:ok, new_cursor} ->
        send(self(), :process_stream)
        {:noreply, [], %{state | cursor: new_cursor}}

      {:error, reason} ->
        Logger.error("Failed to recreate cursor: #{inspect(reason)}")
        Process.send_after(self(), :process_stream, 1000)
        {:noreply, [], state}
    end
  end

  defp handle_mongo_error(e, state) do
    Logger.error("MongoDB error: #{inspect(e)}")
    Process.send_after(self(), :process_stream, 1000)
    {:noreply, [], state}
  end
end
