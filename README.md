# Cnodex

Helper module to simplify working with a C-Node. It is also allows you to start and monitor
an external C-Node process within a supervision tree.

> In my opinion C-Nodes are the **best** option if you need to call into native code.
> The calling overhead is **small**, and on par with the calling overhead of remote node communication.
> And you get **monitoring** abilities through `Node.monitor(:node@host.example)`.
> You can **scale** your C-Nodes onto multiple machines.
>
> So instead of exposing your application to the risks that come with NIFs, you can enclose them in
> an external OS-process. And even better than port drivers, you gain all of the benefits including
> scalability.

Available as a hex-package:

```elixir
{:cnodex, "~> 0.1.0"}
```

## Mount a C-Node inside your supervision tree

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

## Start and call into a C-Node

```
{:ok, pid} = Cnodex.start_link(%{exec_path: "priv/example_client"})
{:ok, reply} = Cnodex.call(pid, {:ping, "hello world"})
```

## Implementation

Your supervisor spawns a gen\_server worker process that is using a node monitor on the C-Node.

You can either provide a running C-Node to connect to, but you must provide an executable with startup arguments that implement a suitable C-Node.

A suitable C-Node prints a `ready_line` to stdout when it is ready to accept messages. This mechanism signals readyness to the gen\_server that will wait for such a `ready_line` on the stdout of the C-Node it just started.
The C-Node startup and readyness handling is synchronous. After a configurable `spawn_inactive_timeout` the gen\_server crashes the `init` procedure, and again supervision can take care of the failued startup.

When you shutdown the Cnodex gen\_server, it will issue a SIGTERM to the OS-pid of the C-Node, to ensure you have no lingering processes.

The safest option to call into the C-Node is going through the `Cnodex.call/2` or `Cnodex.call/3` function.
It will, using a configurable timeout, await a response from the C-Node within the calling process.
In case the C-Node is unavailable, you will receive a proper error, like calling an unavailable gen\_server.

If you don't want your process inbox to be hijacked for the C-Node response, use a `Task` in combination with `Cnodex.call/2`.

In case the C-Node becomes unavailable, the gen\_server will be notified due to the node monitor.
The gen\_server exits too, so that supervision logic can restart the gen\_server and it will start a new C-Node.

## Helper modules for testing

`Cnodex.Distributed` can be used to programatically start and stop a distributed Elixir environment.
This is especially helpful, since you can only use C-Nodes if you have **epmd** and **:net_kernel** running.

So in test cases, you can simply use `Cnodex.Distributed.up()` to start **epmd** and **:net_kernel**.

## Writing a C-Node

This repository provides you with some good starting points for writing a project or package that
encloses a C-Node.

Checkout the following files:

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
    │
    # An example test case on how to test C-Nodes and C-Node communication
    └── cnodex_test.exs
```

In particular `example_client.c` contains a nice boilerplate for writing your own C-Node client that
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

## Performance

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

## Documentation

The docs can be found at [https://hexdocs.pm/cnodex](https://hexdocs.pm/cnodex).

