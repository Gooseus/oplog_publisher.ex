defmodule OplogPublisherTest do
  use ExUnit.Case
  doctest OplogPublisher

  test "greets the world" do
    assert OplogPublisher.hello() == :world
  end
end
