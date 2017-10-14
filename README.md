# Nodex

![](https://github.com/Overbryd/nodex/blob/master/nodex.png?raw=true)

A set of helper modules that enable you to work with **distributed elixir** and **c-nodes**.

Available as a hex-package:

```elixir
{:nodex, "~> 0.1.1"}
```

## Documentation

The docs can be found at [https://hexdocs.pm/nodex](https://hexdocs.pm/nodex).

## Nodex.Distributed

A module to setup a distributed environment programmatically.
It takes care of starting **epmd**, starts **:net_kernel** for you and can start and maintain **child**-nodes.

```elixir
iex> Nodex.Distributed.up
iex> Node.alive?
true
iex> Node.self()
:"master@127.0.0.1"
iex> Nodex.Distributed.spawn_slaves(2)
[:"slave1@127.0.0.1", :"slave2@127.0.0.1"]
```

## Nodex.Cnode

Helper module to simplify working with a C-Node. It is also allows you to start and monitor
an external C-Node process within a supervision tree.

### What is a "Cnode"?

C-Nodes are external os-processes that communicate with the Erlang VM through erlang messaging.
That way you can implement native code and call into it from Elixir in a safe predictable way.
The Erlang VM stays unaffected by crashes of the external process.

> In my opinion C-Nodes are the **best** option if you need to call into native code.
> The calling overhead is **small**, and on par with the calling overhead of remote node communication.
> And you get **monitoring** abilities through `Node.monitor(:node@host.example)`.
> You can **scale** your C-Nodes onto multiple machines.
>
> So instead of exposing your application to the risks that come with NIFs, you can enclose them in
> an external OS-process. And even better than port drivers, you gain all of the benefits including
> scalability.

The repository includes a benchmark comparing local, remote and cnode calling performance:

```console
## VmVsCnodeBench
[20:16:07] 1/4: cnode
[20:16:09] 2/4: cnode direct
[20:16:12] 3/4: local
[20:16:14] 4/4: remote

Finished in 11.49 seconds

## VmVsCnodeBench
benchmark nam iterations   average time 
local            1000000   1.90 µs/op
cnode direct       50000   37.30 µs/op
cnode              50000   41.43 µs/op
remote             50000   48.64 µs/op
```

Executed on a MacBook Pro 2,5GHz.

### Mount a C-Node inside your supervision tree

Mount Cnodex as a worker, and reference it by name:
```elixir
children = [
  worker(Cnodex, [%{exec_path: "priv/example_client"}], name: :ExampleClient)
]
Supervisor.init(children, strategy: :one_for_one)
```

Later call into your C-node through Cnodex:

```elixir
{:ok, reply} = Cnodex.call(:ExampleClient, {:ping, "hello world"})
```

### Start and call into a C-Node

```elixir
{:ok, pid} = Cnodex.start_link(%{exec_path: "priv/example_client"})
{:ok, reply} = Cnodex.call(pid, {:ping, "hello world"})
```

### `Nodex.Cnode` Implementation details

Your supervisor spawns a `GenServer` worker process that is using a node monitor on the C-Node.

You can provide a running C-Node to connect to. You must provide an executable with startup arguments that implement a suitable C-Node.

A suitable C-Node prints a `ready_line` to stdout when it is ready to accept messages.
This mechanism signals readyness to the monitoring process.
The C-Node startup and ready-handling is synchronous. After a configurable `spawn_inactive_timeout` the `init` procedure is interrupted, and again supervision can take care of the failued startup.

When you shutdown `Nodex.Cnode`, it will issue a SIGTERM to the os-pid of the C-Node, to ensure you have no lingering processes.
Although it is even better if you implement some mechanism in the C-Node to ensure it exits properly after it looses the connection to Erlang.

The safest option to call into the C-Node is going through the `Cnodex.call/2` or `Cnodex.call/3` function.
It will, using a configurable timeout, await a response from the C-Node within the calling process.
In case the C-Node is unavailable, you will be thrown a proper exception, because you are calling an unavailable GenServer.

If you don't want your process inbox to be hijacked waiting for the C-Node response, use a `Task` in combination with `Cnodex.call/2`.

In case the C-Node becomes unavailable, the Cnode GenServer terminates too.
Your supervisor can then take care starting a new C-Node.

### Writing a C-Node

This repository provides you with some good starting points for writing a project or package that
encloses a C-Node.

Checkout the following files of this repository:

```
# A proper Makefile is a great base for building C
├── Makefile
│
├── bench
│   │
│   # How to benchmark a C-Node
│   └── vm_vs_cnode_bench.exs
│
# Directory with C source files
├── c_src
│   │
│   # An example C-Node client that connects back to your node
│   └── example_client.c
│
# A mix file that defines a custom task for handling Makefile builds
├── mix.exs
│
# The priv directory should contain your C build artifacts
├── priv
│   │
│   # This is the example C-Node client that gets build
│   └── example_client
│
└── test
    └── nodex
            │
            # An example test case on how to test C-Nodes and C-Node communication
            └── cnode_test.exs
```

In particular [`c_src/example_client.c`](https://github.com/Overbryd/nodex/blob/master/c_src/example_client.c) contains a nice boilerplate for writing your own C-Node client that
connects back to your node. It is fully annotated, so have a look to find out what is going on there.

The general idea behind this is, that you start up a C-program, and in the startup arguments you provide the
connection information to your Elixir node. If everything goes well, your C-program prints a shared message
to STDOUT.
The Elixir side that started the C-program will read all the STDOUT lines written by the C-program.
If the correct shared message appears, it assumes the C-program is now ready to accept messages.
And it will establish a node monitor on the C-program, so that if the connection goes down, the Elixir side
is notified of the loss.

It is best to write the C-program in a way that is exits cleanly as soon as it looses the connection or something goes wrong.
That aligns the C-program with the idea that it can be controlled by a supervisor.

