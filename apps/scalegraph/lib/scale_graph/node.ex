# TODO:
# - Need to take/generate an ID/keypair and address.
defmodule ScaleGraph.Node do
  use GenServer
  require Logger
  alias ScaleGraph.RPC

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, opts)
  end

  def ping(node, dst) do
    Logger.info("Node.ping(#{inspect(dst)})")
    GenServer.call(node, {:cmd, :ping, dst})
  end

  @impl GenServer
  def init(opts) do
    # FIXME: The Node should start the network and RPC servers as supervised
    # children! However, for testing, we also need it to be possible to pass
    # them in from the outside. So they can be specified either as PID/name
    # when started outside, or as a keyword list when started here.
    rpc = Keyword.fetch!(opts, :rpc)
    # Because we accepted an RPC server from the outside, we need to explicitly
    # register this Node process as the handler.
    :ok = RPC.set_handler(rpc)
    state = %{rpc: rpc}
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
  def handle_info({:rpc_request, msg} = req, state) do
    Logger.info("got some RPC request")
    case RPC.typ(req) do
      :ping ->
        Logger.info("responding to a PING request")
        RPC.respond(state.rpc, req, nil)

      _ ->
        Logger.error("Ignoring unexpected RPC: #{inspect(req)}")
    end
  end

  @impl GenServer
  def handle_info({:rpc_response, _} = rpc, state) do
    # At least this is true for now. Might change in the future.
    Logger.warning("Node is not meant to receive RPC responses, ignoring: #{inspect(rpc)}")
    {:noreply, state}
  end

end
