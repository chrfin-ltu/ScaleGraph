defmodule Netsim.UDP do
  use GenServer
  require Logger

  @doc """
  Start UDP network server as a linked process.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, nil, opts)
  end

  @doc """
  Opens a socket and registers the process for receiving messages from the
  network. The `address` is an `{ip, port}` pair.
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
    state = %{socket: nil, owner: nil}
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:connect, {ip, port}, process}, _caller, state) do
    if state.owner || state.socket do
      Logger.error("already connected to UDP network, ignoring")
      {:reply, :ignored, state}
    else
      state = _connect(ip, port, process, state)
      {:reply, :ok, state}
    end
  end

  @impl GenServer
  def handle_cast({:send, dst, payload}, state) do
    if state.socket == nil do
      Logger.error("no socket! Forgot to connect?")
    end

    :ok = :gen_udp.send(state.socket, dst, payload)
    {:noreply, state}
  end

  defp _connect(ip, port, process, state) do
    {:ok, socket} = :gen_udp.open(port, ip: ip, active: true, mode: :binary)
    %{state | owner: process, socket: socket}
  end

  # Called by :gen_udp when a packet comes in over the (real) network.
  # Currently, we discard the source address because it is already in the
  # RPC message. We might want to use it in the future to, e.g.:
  # - Save a few bytes by not duplicating the address in the RPC message and
  #   the UDP/IP header.
  # - Otherwise, if we keep the redundancy, it might make sense to check the
  #   two addresses to ensure they match.
  @impl GenServer
  def handle_info({:udp, _socket, _src_ip, _src_port, payload}, state) do
    Kernel.send(state.owner, {:network, payload})
    {:noreply, state}
  end
end
