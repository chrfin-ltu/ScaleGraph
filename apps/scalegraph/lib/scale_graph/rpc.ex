# TODO:
# - When sending a request, remember the sending process so that the response
#   can be delivered back to the sender.
# - Generate proper message IDs. Ideally configurable (e.g. number of bits).
# - Handle timeouts (no response). Possibly includes re-sending a few times.
# - When requests can time out, a late response has to be handled correctly.
# - When a response is received, the RTT should be included.
# - Handle signatures (signing outgoing, verifying incoming).
# - Seamlessly use either fake or real network.
# - Include this RPC server in a supervision tree.
# - Encoding currently turns a term into a binary representation.
#   The encoding should be made more efficient (compact) in the future.
# - The decoding will then have to be more complex.
# - With a more compact and special-purpose binary message format, we may need
#   to include a version field.
# - It probably makes sense to be able to switch between a plain and
#   straightforward term-based and a more sophisticated (and presumably more
#   error-prone) binary format.
# - Do we handle all messages here (such as consensus)? Or split?
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

  Note that each node has its own RPC instance and so knows the source IP:port
  address, which is essentially its own address. It therefore does not need
  to be supplied explicitly.
  """
  use GenServer

  @id_bits 32 # XXX: using a 32-bit ID for now

  defstruct [
    # {IP, port} of this node
    addr: nil,
    # ID (e.g. public key) of this node
    id: nil,
    # network
    net: nil,
    netmod: Netsim.Fake,
    # handler for incoming RPCs
    handler: nil
  ]

  @doc """
  Start RPC server as a linked process.

  Options:
  - `net: {network implementation module, network process}` (mandatory)
  - `handler: process` (optional, defaults to `self()`)
  """
  def start_link(opts) do
    opts = Keyword.merge(opts, handler: self())
    GenServer.start_link(__MODULE__, opts, opts)
  end

  # --- Functions for sending RPC requests, i.e. making RPC calls ---

  @doc "Send a PING RPC to `dst`."
  def ping(name, dst) do
    GenServer.cast(name, {:request, :ping, dst, nil})
  end

  @doc "Send a FIND-NODES RPC to `dst`."
  def find_nodes(name, dst, target) do
    GenServer.cast(name, {:request, :find_nodes, dst, target})
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
    {netmod, net} = Keyword.fetch!(opts, :net)
    handler = Keyword.fetch!(opts, :handler)

    state = %__MODULE__{
      addr: addr,
      id: id,
      net: net,
      netmod: netmod,
      handler: handler
    }

    netmod.connect(net, addr)
    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:request, typ, dst, data}, state) do
    rpc = new_request(typ, state.addr, dst, data)
    payload = encode(rpc)
    state.netmod.send(state.net, dst, payload)
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
    Kernel.send(state.handler, rpc)
    {:noreply, state}
  end

  @doc "Encode an RPC message to binary for transmission over the network."
  def encode(rpc), do: :erlang.term_to_binary(rpc)

  @doc "Decode a binary RPC message received from the network."
  def decode(rpc) when is_binary(rpc), do: :erlang.binary_to_term(rpc)

  # --- Functions for extracting RPC message fields ---

  @doc "Extract RPC message type, e.g. `:ping`."
  def typ({_tag, {typ, {_src, _dst, _data, _id}}}), do: typ
  @doc "Extract RPC message source address."
  def src({_tag, {_typ, {src, _dst, _data, _id}}}), do: src
  @doc "Extract RPC message destination address."
  def dst({_tag, {_typ, {_src, dst, _data, _id}}}), do: dst
  @doc "Extract RPC message payload data."
  def data({_tag, {_typ, {_src, _dst, data, _id}}}), do: data
  @doc "Extract RPC message ID."
  def id({_tag, {_typ, {_src, _dst, _data, id}}}), do: id

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
