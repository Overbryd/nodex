defmodule Nodex.Distributed do
  @moduledoc """
  A module to help setting up a distributed environment.

  ## Examples

  Starting and stopping a distributed environment:

  ```
  iex> Node.alive?
  false
  iex> Nodex.Distributed.up
  iex> Node.alive?
  true
  iex> Nodex.Distributed.down
  iex> Node.alive?
  false
  ```

  Spawning 2 new slaves:

  ```
  iex> Nodex.Distributed.up
  iex> Nodex.Distributed.spawn_slaves(2)
  [:"slave1@127.0.0.1", :"slave2@127.0.0.1"]
  ```

  Loading a dynamically defined module onto a remote node and call a function on it remotely:

  ```
  iex> Nodex.Distributed.up
  iex> [node] = Nodex.Distributed.spawn_slaves(1)
  iex> {:module, module, object_code, _} = defmodule A, do: def greet, do: "hi from " <> to_string(Node.self)
  iex> Nodex.Distributed.rpc(node, A, :greet, []) # this won't work, A is not present on the remote node
  iex> Nodex.Distributed.load_object_code(node, module, object_code)
  iex> Nodex.Distributed.rpc(node, A, :greet, [])
  "hi from slave1@127.0.0.1"
  ```
  """

  defmodule Badrpc, do: defexception [:message, :reason]

  @doc """
  Starts a distributed environment.

  It will spawn an instance of **epmd** (Erlang Port Mapper Daemon) and start `:net_kernel`.
  Optionally accepts an `sname` and `ip` as argument.

  ## Parameters

    - `sname`: Provide a short name for this node. (default: `"master"`)
    - `ip`: Provide an ip this node should be listening on. (default: `"127.0.0.1"`)
  """
  @spec up(binary(), binary()) :: node()
  def up(master_sname \\ "master", ip \\ "127.0.0.1") do
    spawn_epmd()
    :ok = setup_master(master_sname, ip)
    :"#{master_sname}@#{ip}"
  end

  @doc """
  Stops the distributed environment and all slaves.

  Stops `:net_kernel` and calls `:slave.stop/1` on all connected nodes.
  It will spawn an instance of **epmd** (Erlang Port Mapper Daemon) and start `:net_kernel`.
  """
  @spec down() :: :ok
  def down() do
    Node.list()
    |> Enum.each(&:slave.stop/1)
    :net_kernel.stop()
  end

  @doc """
  Start an instance of the erlang port mapper daemon.

  It looks for the `epmd` executable using `System.find_executable/1` (that looks into the `PATH`
  environment variable).
  Note, that epmd just exits if another instance of it is already running on the same host.
  """
  @spec spawn_epmd() :: {binary(), 0} | {binary(), integer()}
  def spawn_epmd() do
    case System.find_executable("epmd") do
      nil -> raise "could not find epmd in your PATH"
      cmd -> System.cmd(cmd, ["-daemon"])
    end
  end

  @doc """
  Starts `:net_kernel`, `:erl_boot_server`.

  Adds the ip as a slave node to the list of allowed slave hosts.
  Optionally accepts an `sname` and `ip` as argument.

  ## Parameters

    - `sname`: Provide a short name for this node. (default: `"master"`)
    - `ip`: Provide an ip address for this node. (default: `"127.0.0.1"`)
  """
  @spec setup_master(binary(), binary()) :: :ok
  def setup_master(master_sname \\ "master", ip \\ "127.0.0.1") do
    :net_kernel.start([:"#{master_sname}@#{ip}"])
    :erl_boot_server.start([])
    allow_boot(ip)
  end

  @doc """
  Spawn a number of new slaves.

  Optionally accepts an `ip` as argument.
  Slaves are named "slave<index>", index starts at 1. Starting 2 slaves, starts two new nodes `slave1@127.0.0.1` and `slave2@127.0.0.1`

  See `spawn_slave/1` for a description of what is loaded on the newly spawned node.

  Returns a list of node identifiers that have been started.
  """
  @spec spawn_slaves(integer(), binary()) :: [node()]
  def spawn_slaves(num_nodes, ip \\ "127.0.0.1") do
    new_slave_range(num_nodes)
    |> Enum.map(fn index -> "slave#{index}@#{ip}" end)
    |> Enum.map(&Task.async(fn ->
      {:ok, slave} = spawn_slave(&1)
      slave
    end))
    |> Enum.map(&Task.await(&1, 30_000))
  end

  @doc """
  Spawn a slave.

  Add all code paths from this node, transfer elixir configuration
  and ensure all applications are started like on this node.
  """
  @spec spawn_slave(node() | binary()) :: {:ok, node()}
  def spawn_slave(node) when is_atom(node) do
    spawn_slave(to_string(node))
  end
  def spawn_slave(node) do
    [name, host] = String.split(node, "@")
    inet_loader_args = ~c"-loader inet -hosts #{host} -setcookie #{:erlang.get_cookie()}"
    {:ok, node} = :slave.start(to_charlist(host), to_charlist(name), inet_loader_args)
    ensure_ping(node)
    add_code_paths(node)
    transfer_configuration(node)
    ensure_applications_started(node)
    {:ok, node}
  end

  @doc """
  List all nodes that have been started by `Nodex.Distributed`.

  Does not list other nodes connected to this node.
  For a list of all connected nodes use `Node.list/0`, or `Node.list/1`.
  """
  @spec slaves() :: [node()]
  def slaves() do
    Node.list()
    |> Enum.filter(fn node ->
      Regex.match?(~r/^slave(\d+)@/, to_string(node))
    end)
  end

  @doc """
  Load the given object code into module, file on the remote node.

  Just a wrapper to call `:code.load_binary/3` remotely.
  """
  @spec load_object_code(node(), module(), binary()) :: {:module, module()}
  def load_object_code(node, module, object_code) do
    rpc!(node, :code, :load_binary, [module, ~c'(dynamic from #{Node.self})', object_code])
  end

  @doc """
  Load the given module on the remote node.
  """
  @spec load_module(node(), module()) :: any()
  def load_module(node, module) do
    {module, object_code, file} = :code.get_object_code(module)
    rpc!(node, :code, :load_binary, [module, file, object_code])
  end

  @doc """
  Remote procedure call on the given remote node.
  """
  @spec rpc(node(), module(), atom(), [any()]) :: {:ok, any()} | {:badrpc, any()}
  def rpc(node, module, function, args) when is_atom(node) do
    case :rpc.block_call(node, module, function, args) do
      {:badrpc, _reason} = e -> e
      res -> res
    end
  end

  @doc """
  Remote procedure call on the given remote node. Raise on badrpc.
  """
  @spec rpc!(node(), module(), atom(), [any()]) :: any()
  def rpc!(node, module, function, args) when is_atom(node) do
    case :rpc.block_call(node, module, function, args) do
      {:badrpc, reason} ->
        call = if args == [] do
          "#{module}.#{function}/0"
        else
          "#{module}.#{function}/#{Enum.count(args)} with (#{inspect args})"
        end
        raise(Badrpc, message: "rpc failed for #{call} on #{node}, reason: #{inspect reason}", reason: reason)
      res -> res
    end
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

  defp allow_boot(ip) do
    {:ok, ipv4} = :inet.parse_ipv4_address(to_charlist(ip))
    :erl_boot_server.add_slave(ipv4)
  end

  defp ensure_ping(node) do
    :pong = Node.ping(node)
  end

  defp add_code_paths(node) do
    :ok = rpc!(node, :code, :add_paths, [:code.get_path()])
  end

  defp transfer_configuration(node) do
    for {app_name, _, _} <- Application.loaded_applications do
      for {key, val} <- Application.get_all_env(app_name) do
        :ok = rpc!(node, Application, :put_env, [app_name, key, val])
      end
    end
  end

  defp ensure_applications_started(node) do
    rpc(node, Application, :ensure_all_started, [:mix])
    for {app_name, _, _} <- Application.loaded_applications do
      {:ok, _} = rpc!(node, Application, :ensure_all_started, [app_name])
    end
  end
end

