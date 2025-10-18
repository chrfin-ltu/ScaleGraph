defmodule ScaleGraph.Node do
  use GenServer
  require Logger
  alias ScaleGraph.RPC
  alias ScaleGraph.DHT

  defstruct [
    id: nil,
    addr: nil,
    keys: nil,
    rpc: nil,
    dht: nil,
  ]

  @doc """
  Start a Node as a linked process.

  Required options:
  - `:keys` - a `%{priv: priv, pub: pub}` key pair.
  - `:addr` - an `{ip, port}` pair.
  - `:dht` - a DHT process.
  """
  def start_link(opts) do
    opts = massage_opts(opts)
    GenServer.start_link(__MODULE__, opts, opts)
  end

  defp massage_opts(opts) do
    keys = Keyword.fetch!(opts, :keys)
    addr = Keyword.fetch!(opts, :addr)
    id = Keyword.get(opts, :id, Util.key_to_id(keys[:pub]))
    # FIXME: This creates new atoms even when they aren't needed!
    name = :"node_#{inspect(addr)}"
    opts
      |> Keyword.put_new(:id, id)
      |> Keyword.put_new(:name, name)
  end

  def ping(node, dst) do
    # TODO: Handle timeouts more sensibly.
    GenServer.call(node, {:cmd, :ping, dst}, 500)
  end

  @doc """
  Specify which node(s) to use for bootstrapping with `bootstrap: nodes`, where
  `nodes` is a list of one or more `{id, addr}` pairs.
  """
  def join(node, opts \\ []) do
    GenServer.call(node, {:cmd, :join, opts})
  end

  @impl GenServer
  def init(opts) do
    rpc = Keyword.fetch!(opts, :rpc)
    state = %__MODULE__{
      id: Keyword.fetch!(opts, :id),
      addr: Keyword.fetch!(opts, :addr),
      keys: Keyword.fetch!(opts, :keys),
      rpc: rpc,
      dht: Keyword.fetch!(opts, :dht),
    }
    # Because we accepted an RPC server from the outside, we need to explicitly
    # register this Node process as the handler.
    :ok = RPC.set_handler(rpc, Keyword.get(opts, :name))
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:cmd, :ping, dst}, caller, state) do
    spawn(fn ->
      RPC.ping(state.rpc, dst)
      resp =
        receive do
          {:rpc_response, {:ping, _}} = resp ->
            resp
        end
      GenServer.reply(caller, resp)
    end)
    {:noreply, state}
  end

  @impl GenServer
  def handle_call({:cmd, :join, opts}, caller, state) do
    dht = state.dht
    spawn(fn ->
      result = DHT.join(dht, opts)
      GenServer.reply(caller, result)
    end)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:rpc_request, _msg} = req, state) do
    DHT.update(state.dht, RPC.src(req))
    case RPC.typ(req) do
      :ping ->
        _handle_ping(state, req)
      :find_nodes ->
        _handle_node_lookup(state, req)

      _ ->
        Logger.error("Ignoring unexpected RPC: #{inspect(req)}")
    end
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:rpc_response, _} = rpc, state) do
    # At least this is true for now. Might change in the future.
    Logger.warning("Node is not meant to receive RPC responses, ignoring: #{inspect(rpc)}")
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:update, {:rpc_response, _} = resp, _stats}, state) do
    DHT.update(state.dht, RPC.src(resp))
    {:noreply, state}
  end

  # Respond to a PING request.
  defp _handle_ping(state, req) do
    RPC.respond(state.rpc, req, nil)
  end

  # Respond to a FIND-NODE request.
  defp _handle_node_lookup(state, req) do
    id = RPC.data(req)
    nodes = DHT.closest_nodes(state.dht, id)
    RPC.respond(state.rpc, req, nodes)
  end

end
