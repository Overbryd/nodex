defmodule Nodex do
  @moduledoc """
  `Nodex` can be seen as an extenstion to `Node`, providing helping functionality
  around distributed elixir.
  """

  @doc """
  Return the short name of a given node identifier <sname>@host
  """
  @spec sname(node()) :: binary()
  def sname(node) do
    [sname, _host] = String.split(to_string(node), "@")
    sname
  end

  @doc """
  Return the short name of `Node.self/0`.
  """
  @spec sname() :: binary()
  def sname() do
    sname(Node.self())
  end

  @doc """
  Return the host part of `Node.self/0`. somenode@<host>
  """
  @spec host(node()) :: binary()
  def host(node) do
    [_sname, host] = String.split(to_string(node), "@")
    host
  end

  @doc """
  Return the host part of `Node.self/0`.
  """
  @spec host() :: binary()
  def host() do
    host(Node.self())
  end
end
