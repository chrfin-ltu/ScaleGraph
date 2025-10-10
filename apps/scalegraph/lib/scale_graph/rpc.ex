# TODO:
# - Generate proper message IDs. Ideally configurable (e.g. number of bits).
# - Handle timeouts (no response). Possibly includes re-sending a few times.
# - When requests can time out, a late response has to be handled correctly.
# - When a response is received, the RTT should be included.
# - Handle signatures (signing outgoing, verifying incoming).
# - Encoding currently turns a term into a binary representation.
#   The encoding should be made more efficient (compact) in the future.
# - The decoding will then also have to be more complex.
# - With a more compact and special-purpose binary message format, we may need
#   to include a version field.
# - It probably makes sense to be able to switch between a plain and
#   straightforward term-based and a more sophisticated (and presumably more
#   error-prone) binary format.
# - Maybe make handling of unexpected responses configurable? Is there really
#   any point in delivering them to the handler? What can it do?
# - Do we handle all messages here (such as consensus)? Or split?
# - When calling RPCs (i.e. ping/2, find_nodes/3, etc.) we may want to
#   specify options such as timeouts or maximum retries.
#
# NOTE: Because we don't collect multiple transactions into a block to be
# handled in bulk, but instead handle one transaction at a time, messaging
# overhead (i.e. network bandwidth) will be the troughput bottleneck.
# A compact binary message format will therefore be essential for performance.
defmodule ScaleGraph.RPC do
  @moduledoc """
  Module for making remote procedure calls.

  This is essentially a more intelligent "network". It takes care of
  constructing, sending, and receiving RPC messages, including associating
  requests with responses.

  A `:handler` process can be specified as an option to `start_link/1`.
  In that case, the handler is set during initialization (which also connects
  the RPC server to the network.)
  The handler can also be set with `set_handler/1`.

  Incoming (unsolicited) RPC **requests** are delivered to the handler. An RPC
  **response** is delivered to the process that made the corresponding request.
  This can be overridden by specifying the process that should receive the
  response using a `:reply_to` option, for example:

  ```
  RPC.ping(rpc, dst)                      # response is delivered to self()
  RPC.ping(rpc, dst, reply_to: receiver)  # response is delievered to receiver
  ```

  When an unexpected response is received (i.e. one not matching a previously
  outgoing request), this is logged as a warning, and the response is delivered
  to the handler. (This behavior is subject to change.)

  Note that each node has its own RPC instance and so knows the source IP:port
  address, which is essentially its own address. It therefore does not need
  to be supplied explicitly when making RPC calls.
  """
  use GenServer
  require Logger

  # XXX: using a 32-bit ID for now
  @id_bits 32

  defstruct [
    # {IP, port} of this node
    addr: nil,
    # ID (e.g. public key) of this node
    id: nil,
    # network
    net: nil,
    netmod: Netsim.Fake,
    # handler for incoming RPCs
    handler: nil,
    name: nil,
    expected: %{}
  ]

  @doc """
  Start RPC server as a linked process.

  Required options:
  - `net: {network implementation module, network process}` (mandatory)

  Optional:
  - `handler: process`, pid, atom, or via-tuple.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, opts)
  end

  # --- Functions for sending RPC requests, i.e. making RPC calls ---

  @doc """
  Set the handler process and connect to the network (unless already connected).
  """
  def set_handler(name, handler) when not is_nil(handler) do
    GenServer.call(name, {:set_handler, handler})
  end

  @doc "Send a PING RPC to `dst`."
  def ping(name, dst, opts \\ []) do
    reply_to = Keyword.get(opts, :reply_to, self())
    GenServer.cast(name, {:request, :ping, dst, nil, reply_to})
  end

  @doc "Send a FIND-NODES RPC to `dst`."
  def find_nodes(name, dst, target, opts \\ []) do
    reply_to = Keyword.get(opts, :reply_to, self())
    GenServer.cast(name, {:request, :find_nodes, dst, target, reply_to})
  end

  # --- Functions for sending responses ---

  @doc "Send a response to a previous `request`."
  def respond(name, request, data) do
    GenServer.cast(name, {:respond, request, data})
  end

  @impl GenServer
  def init(opts) do
    addr = Keyword.fetch!(opts, :addr)
    id = Keyword.fetch!(opts, :id)
    name = Keyword.get(opts, :name, self())
    {netmod, net} = Keyword.fetch!(opts, :net)
    handler = Keyword.get(opts, :handler)

    state = %__MODULE__{
      addr: addr,
      id: id,
      net: net,
      netmod: netmod,
      handler: handler,
      name: name
    }

    if handler != nil do
      :ok = netmod.connect(net, addr, name)
    end
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:set_handler, handler}, _caller, state) do
    if state.handler == nil do
      :ok = state.netmod.connect(state.net, state.addr, state.name)
    end
    state = Map.put(state, :handler, handler)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_cast({:request, typ, dst, data, reply_to}, state) do
    rpc = new_request(typ, state.addr, dst, data)
    payload = encode(rpc)
    state.netmod.send(state.net, dst, payload)
    # Remember the request for later so we can map the response to it.
    id = id(rpc)
    timestamp = System.monotonic_time()
    state = put_in(state.expected[id], {reply_to, rpc, timestamp})
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:respond, request, data}, state) do
    rpc = response(request, data)
    dst = dst(rpc)
    payload = encode(rpc)
    state.netmod.send(state.net, dst, payload)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:network, payload}, state) do
    rpc = decode(payload)

    state =
      cond do
        request?(rpc) ->
          _handle_request(rpc, state)

        response?(rpc) ->
          _handle_response(rpc, state)

        :else ->
          Logger.error("RPC: neither request nor response, passing to handler")
          _handle_request(rpc, state)
      end

    {:noreply, state}
  end

  # The RPC message is a decoded (term, not binary) message.
  defp _handle_request(rpc, state) do
    pid = GenServer.whereis(state.handler)
    try do
      Kernel.send(pid, rpc)
    rescue
      e ->
        Logger.error("RPC.deliver_request: #{inspect(e)}")
    end
    state
  end

  defp _handle_response(rpc, state) do
    id = id(rpc)

    case state.expected[id] do
      # TODO: Do something useful with request and timestamp.
      {reply_to, _request, _timestamp} ->
        pid = GenServer.whereis(reply_to)
        try do
          Kernel.send(pid, rpc)
        rescue
          e ->
            Logger.error("RPC.deliver_response to caller: #{inspect(e)}")
        end
        Map.put(state, :expected, Map.delete(state.expected, id))

      nil ->
        Logger.warning("RPC.deliver_response: orphan RPC response, passing to handler")
        pid = GenServer.whereis(state.handler)
        try do
          Kernel.send(pid, rpc)
        rescue
          e ->
            Logger.error("RPC.deliver_response to handler: #{inspect(e)}")
        end
        state
    end
  end

  @doc "Encode an RPC message to binary for transmission over the network."
  def encode(rpc), do: :erlang.term_to_binary(rpc)

  @doc "Decode a binary RPC message received from the network."
  def decode(rpc) when is_binary(rpc), do: :erlang.binary_to_term(rpc)

  # --- Functions for extracting RPC message fields ---

  @doc "Extract RPC message type, e.g. `:ping`."
  def typ({_tag, {typ, {_src, _dst, _data, _id}}} = _rpc), do: typ
  @doc "Extract RPC message source address."
  def src({_tag, {_typ, {src, _dst, _data, _id}}} = _rpc), do: src
  @doc "Extract RPC message destination address."
  def dst({_tag, {_typ, {_src, dst, _data, _id}}} = _rpc), do: dst
  @doc "Extract RPC message payload data."
  def data({_tag, {_typ, {_src, _dst, data, _id}}} = _rpc), do: data
  @doc "Extract RPC message ID."
  def id({_tag, {_typ, {_src, _dst, _data, id}}} = _rpc), do: id

  @doc "Is this RPC message a request?"
  def request?({tag, {_typ, {_src, _dst, _data, _id}}} = _rpc) do
    tag == :rpc_request
  end

  @doc "Is this RPC message a response?"
  def response?({tag, {_typ, {_src, _dst, _data, _id}}} = _rpc) do
    tag == :rpc_response
  end

  # --- Functions for constructing requests ---

  defp new_request(typ, src, dst, data) do
    id = generate_id()
    {:rpc_request, {typ, {src, dst, data, id}}}
  end

  # --- Functions for constructing responses ---

  @doc "Constructs a response message to the given RPC request."
  def response(rpc_request, data \\ nil)

  def response({:rpc_request, {:ping, _}} = rpc, _data) do
    new_response(rpc, nil)
  end

  def response({:rpc_request, {:find_nodes, _}} = rpc, data) do
    new_response(rpc, data)
  end

  def response(rpc, _data) do
    raise "cannot make response to unexpected RPC: #{inspect(rpc)}"
  end

  defp new_response({:rpc_request, {typ, {src, dst, _data, id}}}, reply_data) do
    {:rpc_response, {typ, {dst, src, reply_data, id}}}
  end

  # TODO: number of bits should be configurable.
  # May need to depend on the state, depending on how configurable.
  defp generate_id(), do: Util.rand_bits(@id_bits)
end
