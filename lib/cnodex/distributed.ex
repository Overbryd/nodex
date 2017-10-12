defmodule Cnodex.Distributed do

  def up(master_sname \\ "primary") do
    spawn_epmd()
    setup_master(master_sname)
  end

  def down() do
    Node.list()
    |> Enum.map(&:slave.stop/1)
    :net_kernel.stop()
  end

  def spawn_epmd() do
    System.cmd "epmd", ["-daemon"]
  end

  def setup_master(master_sname \\ "primary") do
    :net_kernel.start([:"#{master_sname}@127.0.0.1"])
    :erl_boot_server.start([])
    allow_boot(~c"127.0.0.1")
  end

  def spawn_slaves(num_nodes) do
    new_slave_range(num_nodes)
    |> Enum.map(fn index -> "slave#{index}@127.0.0.1" end)
    |> Enum.map(&Task.async(fn -> spawn_slave(&1) end))
    |> Enum.map(&Task.await(&1, 30_000))
  end

  def spawn_slave(node) do
    [name, host] = String.split(node, "@")
    inet_loader_args = ~c"-loader inet -hosts 127.0.0.1 -setcookie #{:erlang.get_cookie()}"
    {:ok, node} = :slave.start(to_charlist(host), to_charlist(name), inet_loader_args)
    ensure_ping(node)
    add_code_paths(node)
    transfer_configuration(node)
    ensure_applications_started(node)
    {:ok, node}
  end

  def slaves() do
    Node.list()
    |> Enum.filter(fn node ->
      Regex.match?(~r/^slave(\d+)@/, to_string(node))
    end)
  end

  defp new_slave_range(num_nodes) do
    last = Enum.map(Node.list(), fn node ->
      case Regex.scan(~r/^slave(\d+)@/, to_string(node), capture: :all_but_first) do
        [[i]] -> String.to_integer(i)
        _ -> 0
      end
    end)
    |> Enum.max(fn -> 0 end)
    (last + 1)..(last + num_nodes)
  end

  def load_module(module, node) do
    {^module, object_code, file} = :code.get_object_code(module)
    rpc(node, :code, :load_binary, [module, file, object_code])
  end

  def rpc(node, module, function, args) when is_atom(node) do
    case :rpc.block_call(node, module, function, args) do
      {:badrpc, reason} -> raise("badrpc, #{inspect reason}")
      res -> res
    end
  end

  defp allow_boot(host) do
    {:ok, ipv4} = :inet.parse_ipv4_address(host)
    :erl_boot_server.add_slave(ipv4)
  end

  defp ensure_ping(node) do
    :pong = Node.ping(node)
  end

  defp add_code_paths(node) do
    :ok = rpc(node, :code, :add_paths, [:code.get_path()])
  end

  defp transfer_configuration(node) do
    for {app_name, _, _} <- Application.loaded_applications do
      for {key, val} <- Application.get_all_env(app_name) do
        :ok = rpc(node, Application, :put_env, [app_name, key, val])
      end
    end
  end

  defp ensure_applications_started(node) do
    rpc(node, Application, :ensure_all_started, [:mix])
    for {app_name, _, _} <- Application.loaded_applications do
      {:ok, _} = rpc(node, Application, :ensure_all_started, [app_name])
    end
  end
end

