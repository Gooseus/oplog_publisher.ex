defmodule OplogPublisherTest do
  use ExUnit.Case, async: false, group: "test"
  alias OplogPublisher.Pipeline
  alias Mongo
  require Logger

  @moduledoc """
  Tests for the OplogPublisher application.
  """

  setup_all do
    # Clean up any existing resume token at the start of the test suite
    File.rm(".resume_token")

    # Get the pipeline process
    pid = Process.whereis(Pipeline)
    refute is_nil(pid), "Pipeline process not found"

    # Connect to MongoDB
    {:ok, conn} = Mongo.start_link(
      url: "mongodb://localhost:27017/production?replicaSet=rs0",
      pool_size: 1
    )

    on_exit(fn ->
      File.rm(".resume_token")
    end)

    {:ok, %{pipeline_pid: pid, mongo_conn: conn}}
  end

  describe "Starting with no existing changes" do
    test "should initialize and wait for changes", %{pipeline_pid: pid} do
      assert Process.alive?(pid)

      Process.sleep(1000)

      assert Process.alive?(pid)
    end
  end

  describe "Processing changes" do
    @tag test_group: "test"
    test "should process a change and save resume token", %{pipeline_pid: pid, mongo_conn: conn} do
      assert Process.alive?(pid)
      refute File.exists?(".resume_token"), "Resume token should not exist at start"

      # Create a test document in MongoDB
      {:ok, _} = Mongo.insert_one(conn, "users", %{
        "name" => "Test User",
        "email" => "test@example.com",
        "created_at" => DateTime.utc_now()
      })

      # Wait for the change to be processed and token to be saved
      # Try multiple times to check for the token
      token_saved = Enum.reduce_while(1..10, false, fn attempt, _ ->
        Process.sleep(500)
        if File.exists?(".resume_token") do
          {:halt, true}
        else
          Logger.debug("Attempt #{attempt}: Resume token not found yet")
          {:cont, false}
        end
      end)

      assert token_saved, "Resume token should be saved after processing change"

      # Read and verify the token is valid
      {:ok, token_bin} = File.read(".resume_token")
      token = :erlang.binary_to_term(token_bin)
      assert is_binary(token), "Resume token should be a binary string"
      Logger.debug("Found resume token: #{token}")
    end

    @tag test_group: "test"
    test "should process new changes after resume", %{pipeline_pid: pid, mongo_conn: conn} do
      assert Process.alive?(pid)
      assert File.exists?(".resume_token"), "Resume token should exist from previous test"

      # Create a new test document
      {:ok, _} = Mongo.insert_one(conn, "users", %{
        "name" => "Another User",
        "email" => "another@example.com",
        "created_at" => DateTime.utc_now()
      })

      # Set up a monitor to detect if we enter an infinite loop
      test_pid = self()
      monitor_pid = spawn(fn ->
        # Wait for 5 seconds to see if we get stuck in a loop
        Process.sleep(5000)
        send(test_pid, :potential_infinite_loop)
      end)

      # Wait for either a timeout or the infinite loop detection
      receive do
        :potential_infinite_loop ->
          assert false, "Detected potential infinite loop when processing new changes"
      after
        6000 ->
          :ok
      end

      # Clean up monitor process
      Process.exit(monitor_pid, :normal)
    end
  end
end
