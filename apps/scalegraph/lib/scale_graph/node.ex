defmodule ScaleGraph.Node do
  use GenServer
  require Logger
  alias ScaleGraph.RPC

  defstruct [
    id: nil,
    addr: nil,
    keys: nil,
    rpc: nil,
  ]

  @doc """
  Start a Node as a linked process.

  Required options:
  - `:keys` - a `%{priv: priv, pub: pub}` key pair.
  - `:addr` - an `{ip, port}` pair.
  """
  def start_link(opts) do
    opts = massage_opts(opts)
    GenServer.start_link(__MODULE__, opts, opts)
  end

  defp massage_opts(opts) do
    keys = Keyword.fetch!(opts, :keys)
    addr = Keyword.fetch!(opts, :addr)
    id = Keyword.get(opts, :id, Util.key_to_id(keys[:pub]))
    name = :"node_#{inspect(addr)}"
    opts
      |> Keyword.put_new(:id, id)
      |> Keyword.put_new(:name, name)
  end

  def ping(node, dst) do
    # TODO: Handle timeouts more sensibly.
    GenServer.call(node, {:cmd, :ping, dst}, 500)
  end

  @impl GenServer
  def init(opts) do
    keys = opts[:keys]
    id = opts[:id]
    addr = opts[:addr]
    rpc = opts[:rpc]
    # Because we accepted an RPC server from the outside, we need to explicitly
    # register this Node process as the handler.
    :ok = RPC.set_handler(rpc, Keyword.get(opts, :name))
    state = %__MODULE__{
      id: id,
      addr: addr,
      keys: keys,
      rpc: rpc
    }
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
  def handle_info({:rpc_request, _msg} = req, state) do
    case RPC.typ(req) do
      :ping ->
        RPC.respond(state.rpc, req, nil)

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

end
