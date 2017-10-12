defmodule CnodexTest do
  use ExUnit.Case
  doctest Cnodex

  setup_all(_) do
    Distributed.up
  end

  test "greets the world" do
    {:ok, pid} = Cnodex.start_link(%{exec_path: "priv/example_client"})
    {:ok, reply} = Cnodex.call(pid, {:ping, "hello world"})
    assert {:pong, "hello world"} = reply
  end

  test "greets the world with already started cnode" do
    cnode = :"foobar@127.0.0.1"
    {:ok, _state} = Cnodex.spawn_cnode(%{
      exec_path: "priv/example_client",
      cnode: cnode,
      sname: "foobar",
      hostname: "127.0.0.1",
      ready_line: "foobar@127.0.0.1 ready"
    })
    {:ok, pid} = Cnodex.start_link(%{
      exec_path: "priv/example_client",
      cnode: cnode
    })
    {:ok, reply} = Cnodex.call(pid, {:ping, "hello world"})
    assert {:pong, "hello world"} = reply
  end

  test "fails when executable does not activate within spawn_inactive_timeout" do
    assert {:stop, :spawn_inactive_timeout} = Cnodex.init(%{
      exec_path: "priv/example_client",
      spawn_inactive_timeout: 0
    })
  end

  test "fails when connection cannot be established" do
    assert {:stop, :unable_to_establish_connection} = Cnodex.init(%{
      exec_path: "priv/example_client",
      sname: "unconnectable",
      ready_line: "initialising unconnectable@#{Cnodex.node_hostname}",
    })
  end

  test "fails when cnode exits unexpectedly" do
    assert {:stop, :cnode_unexpected_exit} = Cnodex.init(%{exec_path: "priv/just_exit"})
  end
end

