defmodule VmVsCnodeBench do
  use Benchfella

  @echo_module (quote do
    defmodule Echo do
      def listen do
        receive do
          {:ping, msg, from} ->
            send(from, {:pong, msg})
            Echo.listen()
          _ -> Echo.listen()
        end
      end
    end
  end)

  setup_all do
    Code.eval_quoted(@echo_module)
    local_pid = spawn(Echo, :listen, [])
    # start a distributed environment
    Nodex.Distributed.up
    # spawn a slave
    [slave] = Nodex.Distributed.spawn_slaves(1)
    Nodex.Distributed.rpc(slave, Code, :eval_quoted, [@echo_module])
    remote_pid = Node.spawn_link(slave, Echo, :listen, [])
    # spawn a cnode
    {:ok, cnode_pid} = Nodex.Cnode.start_link(%{exec_path: "priv/example_client"})
    # get the node
    cnode = Nodex.Cnode.cnode(cnode_pid)
    # pass down references to benchmarks
    {:ok, {local_pid, remote_pid, cnode_pid, cnode}}
  end

  def response do
    receive do
      {:pong, msg} -> {:ok, {:pong, msg}}
    after
      1000 -> :timeout
    end
  end

  bench "local" do
    {pid, _, _, _} = bench_context
    send(pid, {:ping, "hello", self()})
    {:ok, {:pong, "hello"}} = response()
  end

  bench "remote" do
    {_, pid, _, _} = bench_context
    send(pid, {:ping, "hello", self()})
    {:ok, {:pong, "hello"}} = response()
  end

  bench "cnode" do
    {_, _, pid, _} = bench_context
    {:ok, {:pong, "hello"}} = Nodex.Cnode.call(pid, {:ping, "hello"})
  end

  bench "cnode direct" do
    {_, _, _, cnode} = bench_context
    send({nil, cnode}, {:ping, "hello"})
    {:ok, {:pong, "hello"}} = response()
  end

end

