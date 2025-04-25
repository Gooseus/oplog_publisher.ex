defmodule StreamStepper do
  require Logger

  @moduledoc """
  Helpers to pull items from an infinite (or long-lived) Enumerable
  without ever closing it.
  """

  @type cont() :: {:cont, any()} | {:suspend, any()}

  @doc """
  Take *up to* `count` items from `stream`, returning `{messages, new_cont}`.
  If there are fewer than `count` messages available right now,
  the stream is just left suspended and `messages` will be shorter.
  """
  def take_n(stream, cont, 0), do: {[], cont, stream}

  def take_n(stream, cont, count) when count > 0 do
    case next_item(stream, cont) do
      {:no_event, new_cont, stream} ->
        {[], new_cont, stream}

      {next, next_cont, next_stream} ->
        {final, final_cont, final_stream} = take_n(next_stream, next_cont, count - 1)
        {[next | final], final_cont, final_stream}
    end
  end

  @doc """
  Pull exactly one item (if available) from `stream`, returning:
    - `{:no_event, cont}` if the cursor yielded nothing (e.g. maxAwaitTime expired)
    - `{item, new_cont}` on success
  """
  def next_item(stream, cont) when is_function(cont) do
    next_item(stream, {:cont, cont})
  end

  def next_item(stream, cont) do
    try do
      # We use reduce/3 directly so we can suspend rather than halt the stream:
      case Enumerable.reduce(stream, cont, fn element, _acc -> {:suspend, [element]} end) do
        {:suspended, [], _new_cont} ->
          {:no_event, cont, stream}

        {:suspended, [nil], new_cont} ->
          {:no_event, new_cont, stream}

        {:suspended, [item], new_cont} ->
          {item, new_cont, stream}

        other ->
          raise "Unexpected reduce result: #{inspect(other)}"
      end
    rescue
      e ->
        Logger.error(
          "Unexpected error in next_item: #{Exception.format(:error, e, __STACKTRACE__)}"
        )

        {:no_event, cont, stream}
    end
  end
end
