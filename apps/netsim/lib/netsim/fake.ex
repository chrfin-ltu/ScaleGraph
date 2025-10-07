defmodule Netsim.Fake do
  @moduledoc """
  A fake/simulated network that passes messages directly between processes.
  """
  use GenServer

  defstruct nodes: nil

  def start_link(opts) do
    GenServer.start_link(__MODULE__, nil, opts)
  end

  @doc """
  Connect a process to the network so it can receive network messages.

  The destination `address` (as an `{ip, port}` pair) is mapped to the
  process. Messages destined for this address are delivered to the connected
  process. Any number of processes can connect, but there can only be one
  process per address.
  """
  def connect(net, address, process \\ self())

  def connect(net, {_ip, _port} = dst, process) do
    GenServer.call(net, {:connect, dst, process})
  end

  @doc """
  Send a (binary) `payload` to destination address `dst`.
  """
  def send(net, {_ip, _port} = dst, payload) do
    GenServer.cast(net, {:send, dst, payload})
  end

  @impl GenServer
  def init(_opts) do
    state = %__MODULE__{
      nodes: %{}
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:connect, dst, process}, _caller, state) do
    state = put_in(state.nodes[dst], process)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_cast({:send, dst, payload}, state) do
    target = state.nodes[dst]
    Kernel.send(target, {:network, payload})
    {:noreply, state}
  end
end
