defmodule Nodex.Cnode do
  @moduledoc """
  A module to help calling into and maintaining C-nodes.
  """

  use GenServer
  require Logger

  @type init_args() :: %{
    exec_path: binary(),
    ready_line: binary(),
    spawn_inactive_timeout: integer(),
    sname: binary(),
    hostname: binary(),
    os_pid: integer()
  }
  @type pid_or_name() :: pid() | atom()

  @doc """
  Starts a GenServer that will start and monitor a C-Node.

  ## Parameters

    - `init_args`: A map providing configuration on how to start a C-Node.
      - `:exec_path` _required_ provide a path to the C-Node executable.
      - `:ready_line` a custom message that is awaited on the STDOUT of the C-Node.
      - `:spawn_inactive_timeout` set a timeout in milliseconds after the C-Node is considered
        unresponsive before receiving the ready_line.
  """
  @spec start_link(init_args()) :: {:ok, pid()} | {:error, any()}
  def start_link(init_args, opts \\ []) do
    GenServer.start_link(__MODULE__, init_args, opts)
  end

  def init(args) do
    unless Node.alive? do
      raise "Node is not alive. Cannot connect to a cnode."
    end
    sname = Map.get_lazy(args, :sname, &random_sname/0)
    hostname = Map.get_lazy(args, :hostname, &node_hostname/0)
    cnode = :"#{sname}@#{hostname}"
    state = %{
      exec_path: Map.fetch!(args, :exec_path),
      sname: sname,
      hostname: hostname,
      cnode: cnode,
      ready_line: Map.get(args, :ready_line, "#{cnode} ready"),
      spawn_inactive_timeout: Map.get(args, :spawn_inactive_timeout, 5000),
      os_pid: Map.get(args, :os_pid, nil)
    }
    init_cnode(state)
  end

  defp random_sname, do: :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
  defp node_hostname, do: Node.self() |> to_string |> String.split("@") |> List.last
  defp node_sname, do: Node.self() |> to_string |> String.split("@") |> List.first

  defp init_cnode(%{cnode: cnode} = state) do
    case establish_connection(state) do
      {:ok, state} -> {:ok, state}
      _ ->
        Logger.debug("connection to #{cnode} failed, spawning")
        spawn_cnode(state)
    end
  end

  defp establish_connection(%{cnode: cnode} = state) do
    if Node.connect(cnode) do
      Logger.debug("connected to #{cnode}")
      Node.monitor(cnode, true)
      {:ok, state}
    else
      {:stop, :unable_to_establish_connection}
    end
  end

  def spawn_cnode(%{
    exec_path: exec_path,
    sname: sname,
    hostname: hostname
  } = state) do
    cookie = :erlang.get_cookie()
    tname = node_sname()
    port = Port.open({:spawn_executable, exec_path}, [
      :binary,
      :exit_status,
      :stderr_to_stdout,
      line: 4096,
      args: [sname, hostname, cookie, tname],
    ])
    os_pid = Keyword.get(Port.info(port), :os_pid)
    state = Map.put(state, :os_pid, os_pid)
    await_cnode_ready(port, state)
  end

  defp await_cnode_ready(port, %{
    ready_line: ready_line
  } = state) do
    spawn_inactive_timeout = Map.get(state, :spawn_inactive_timeout, 5000)
    receive do
      {^port, {:data, {:eol, ^ready_line}}} ->
        establish_connection(state)
      {^port, {:data, {:eol, line}}} ->
        Logger.debug("c-node is saying: #{line}")
        await_cnode_ready(port, state)
      {^port, {:exit_status, exit_status}} ->
        Logger.debug("unexpected c-node exit: #{exit_status}")
        {:stop, :cnode_unexpected_exit}
      m ->
        IO.inspect(m)
        raise "unhandled msg while waiting for cnode ready"
    after
      spawn_inactive_timeout ->
        {:stop, :spawn_inactive_timeout}
    end
  end

  def handle_info({:nodedown, _cnode}, state) do
    {:stop, :nodedown, state}
  end

  def handle_info(msg, state) do
    Logger.warn "unhandled handle_info: #{inspect msg}"
    {:noreply, state}
  end

  def handle_call(:cnode, _from, %{cnode: cnode} = state) do
    {:reply, {:ok, cnode}, state}
  end

  def terminate(_reason, %{os_pid: os_pid}) when os_pid != nil do
    System.cmd("kill", ["-9", os_pid])
    :normal
  end

  @doc """
  Returns the `:"sname@host"` identifier for the C-Node.
  With this you can leverage `Node.monitor/2` or `Kernel.send/2` for your own purposes.

  ## Parameters

    - `pid_or_name`: The pid or name of the Cnode GenServer

  """
  @spec cnode(pid_or_name()) :: node()
  def cnode(pid_or_name) do
    {:ok, cnode} = GenServer.call(pid_or_name, :cnode)
    cnode
  end

  @doc """
  Call into the C-Node managed by Cnode referenced by pid or name.
  Returns the response or an error after a configurable timeout.

  ## Parameters

    - `pid_or_name`: The pid or name of the Cnode GenServer
    - `msg`: The message for the C-Node
    - `timeoout`: (_optional_, default: 5000) the time in milliseconds that is waited for a response.
  """
  @spec call(pid_or_name(), any(), integer()) :: {:ok, any()} | {:error, :timeout}
  def call(pid_or_name, msg, timeout \\ 5000) do
    node = cnode(pid_or_name)
    send({nil, node}, msg)
    await_response(timeout)
  end

  defp await_response(:infinite) do
    receive do
      response -> {:ok, response}
    end
  end

  defp await_response(timeout) when is_integer(timeout) do
    receive do
      response -> {:ok, response}
    after
      timeout -> {:error, :timeout}
    end
  end

end

