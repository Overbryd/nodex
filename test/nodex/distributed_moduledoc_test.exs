defmodule Nodex.DistributedModuledocTest do
  use ExUnit.Case
  doctest Nodex.Distributed

  setup(_) do
    Nodex.Distributed.down
    :ok
  end
end

