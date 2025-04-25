defmodule OplogPublisher.Pipeline do
  use Broadway
  alias Broadway.Message
  require Logger

  @type js_prefix :: String.t()
  @type nats_url :: String.t()
  @js_prefix Application.compile_env!(:oplog_publisher, :js_subject_prefix)

  @type gnat_conn :: pid() | {atom(), pid()} | {:via, atom(), pid()}
  @type gnat_error :: {:error, term()} | {:error, atom(), term()}

  @spec start_link(any()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(_opts) do
    # Start the Gnat connection first
    case Gnat.start_link(%{
           host: "localhost",
           port: 4222,
         }) do
      {:ok, gnat} ->
        Logger.info("Starting Broadway pipeline with NATS connection")
        Broadway.start_link(__MODULE__,
          name: __MODULE__,
          producer: [
            module: {OplogPublisher.Producer, []},
            concurrency: 1
          ],
          processors: [
            default: [
              concurrency: 1,
              min_demand: 0,
              max_demand: 1
            ]
          ],
          context: %{gnat: gnat}
        )
      {:error, reason} ->
        Logger.error("Failed to start Gnat connection: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def init(opts) do
    Logger.info("Initializing pipeline with opts: #{inspect(opts)}")
    {:ok, opts}
  end

  @impl true
  @spec handle_message(any(), Broadway.Message.t(), any()) :: Broadway.Message.t()
  def handle_message(:default, %Message{data: change} = msg, context) when is_map(change) do
    Logger.info("Pipeline handling message: #{inspect(change["operationType"])} on #{change["ns"]["db"]}.#{change["ns"]["coll"]}")
    # build your NATS subject:
    subj =
      [
        @js_prefix,
        change["ns"]["db"],
        change["ns"]["coll"],
        change["operationType"]
      ] |> Enum.join(".")

    payload = %{
      id: change["documentKey"]["_id"],
      ts: change["clusterTime"],
      data: Map.get(change, "fullDocument", Map.get(change, "updateDescription", %{}))
    }

    Logger.debug("Publishing to subject: #{subj}")
    Logger.debug("Payload: #{inspect(payload)}")

    # publish to JetStream using the persistent connection
    case publish(context.gnat, subj, payload) do
      :ok ->
        Logger.info("Successfully published message to #{subj}")
        msg
      {:error, reason} ->
        Logger.error("Publish failed: #{inspect(reason)}")
        Message.failed(msg, reason)
    end
  end

  @spec handle_message(any(), Broadway.Message.t(), any()) :: Broadway.Message.t()
  def handle_message(:default, msg, _context) do
    Logger.warning("Received unhandled message: #{inspect(msg, pretty: true)}")
    msg
  end


  @impl true
  def handle_batch(_batcher, messages, batch_info, _context) do
    Logger.info("Handling batch of #{length(messages)} messages, batch_info: #{inspect(batch_info)}")
    messages
  end

  # Partition by collection to allow concurrent processing while maintaining order within collections
  # defp partition_key(message) do
  #   ns = message.data["ns"]
  #   "#{ns["db"]}.#{ns["coll"]}" |> :erlang.phash2()
  # end

  @spec publish(pid(), String.t(), map()) :: :ok | {:error, term()}
  defp publish(gnat, subject, payload) do
    try do
      encoded = Jason.encode!(payload)
      :ok = Gnat.pub(gnat, subject, encoded)
    rescue
      e in Jason.EncodeError -> {:error, {:encode_error, e.message}}
    catch
      :exit, reason -> {:error, {:exit, reason}}
      :throw, reason -> {:error, {:throw, reason}}
    end
  end
end
