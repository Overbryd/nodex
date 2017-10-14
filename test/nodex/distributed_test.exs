defmodule Nodex.DistributedTest do
  use ExUnit.Case
  alias Nodex.Distributed
  # for doctest see test/nodex/distributed_moduledoc_test.exs

  setup_all(_) do
    Distributed.up
    :ok
  end

  setup(_) do
    # stop slaves that might have not been cleaned up
    Node.list() |> Enum.each(&:slave.stop/1)
    :ok
  end

  test "spawn a slave" do
    {:ok, node} = Distributed.spawn_slave(:"subnode@127.0.0.1")
    assert :"subnode@127.0.0.1" == node
    assert [node] == Node.list()
  end

  test "spawn a number of slaves" do
    assert [
      :"slave1@127.0.0.1",
      :"slave2@127.0.0.1",
    ] == Distributed.spawn_slaves(2)
    assert [
      :"slave3@127.0.0.1"
    ] == Distributed.spawn_slaves(1)
  end

end

