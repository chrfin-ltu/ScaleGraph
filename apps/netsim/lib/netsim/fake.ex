defmodule Netsim.Fake do
  @moduledoc """
  A fake/simulated network that passes messages directly between processes.

  It behaves like UDP in the sense that message can be lost, e.g. when the
  destination process is not alive.
  However, it simulates/abstracts away all lower layers.
  """
  use GenServer
  require Logger

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

  # Note that this is not exactly the equivalent of UDP.handle_info(:udp, ...)
  # as that receives an incoming packet from the network and has to deliver it
  # to the owner process that is expecting messages.
  # Here, we directly send messages from the sender to the destination, since
  # there is no actual lower-level network involved. So when we fail here, it
  # is equivalent to no socket being open at all. (For UDP, there is a socket,
  # but nobody is ready to handle what was received from the socket.)
  @impl GenServer
  def handle_cast({:send, dst, payload}, state) do
    target = state.nodes[dst]
    pid = GenServer.whereis(target)
    try do
      Kernel.send(pid, {:network, payload})
    rescue
      e -> Logger.error("Fake: destination temporarily down? #{inspect(e)}")
    end
    {:noreply, state}
  end
end
