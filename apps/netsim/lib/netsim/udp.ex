defmodule Netsim.UDP do
  use GenServer
  require Logger

  @doc """
  Start UDP network server as a linked process.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, opts)
  end

  @doc """
  Opens a socket and registers the process for receiving messages from the
  network. The `address` is an `{ip, port}` pair.

  If already connected, the socket is not opened, but the process is
  "connected", which allows a different process to be connected to an existing
  socket.

  The process can be a PID, an atom (naming a registered process), or a via
  tuple of the form `{:via, registry_module, {registry_process, key}}`, where
  `key` is an arbitrary term.
  """
  def connect(net, address, process \\ self())

  def connect(net, {_ip, _port} = bind_addr, process) do
    GenServer.call(net, {:connect, bind_addr, process})
  end

  @doc """
  Send a (binary) `payload` to destination address `dst`.
  """
  def send(net, {_ip, _port} = dst, payload) do
    GenServer.cast(net, {:send, dst, payload})
  end

  @impl GenServer
  def init(opts) do
    state = %{socket: nil, owner: nil}
    case Keyword.get(opts, :connect) do
      nil ->
        # :connect is optional
        # TODO: might want to distinguish missing from explicitly `nil`
        {:ok, state}

      {{ip, port}, owner} ->
        #Logger.info("UDP.init: connecting")
        state = _connect(ip, port, owner, state)
        {:ok, state}

      bad ->
        Logger.error("UDP.init: bad connect: #{inspect(bad)}")
        {:stop, "bad connect param"}
    end
  end

  @impl GenServer
  def handle_call({:connect, {ip, port}, process}, _caller, state) do
    state = Map.put(state, :owner, process)
    if state.socket do
      #Logger.warning("UDP.connect: already connected, ignoring")
      {:reply, :ok, state}
    else
      state = _connect(ip, port, process, state)
      {:reply, :ok, state}
    end
  end

  @impl GenServer
  def handle_cast({:send, dst, payload}, state) do
    if state.socket == nil do
      Logger.error("UDP.send: no socket! Forgot to connect?")
    end
    # Let it crash!
    :ok = :gen_udp.send(state.socket, dst, payload)
    {:noreply, state}
  end

  defp _connect(ip, port, process, state) do
    # TODO: make e.g. {:error :eaddrinuse} more explicit?
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
  #
  # The owner process may be temporarily down when we try to deliver a message.
  # For now, we log an error and ignore it (drop the message). Might try to do
  # something more intelligent in the future.
  @impl GenServer
  def handle_info({:udp, _socket, _src_ip, _src_port, payload}, state) do
    pid = GenServer.whereis(state.owner)
    try do
      Kernel.send(pid, {:network, payload})
    rescue
      e -> Logger.error("UDP: owner temporarily down? #{inspect(e)}")
    end
    {:noreply, state}
  end
end
