defmodule ScaleGraph.NodeSupervisor do
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, opts)
  end

  # FIXME: Need to take (better) names from outside!
  @impl Supervisor
  def init(opts) do
    addr = opts[:addr]
    net_opts = opts
      |> Keyword.put(:name, :network_name)
      |> Keyword.put(:connect, {addr, :rpc_name})
    node_opts = opts
      |> Keyword.put(:name, :node_name)
      |> Keyword.put(:rpc, :rpc_name)
    netmod = Keyword.get(opts, :net_adapter, Netsim.UDP)
    rpc_opts = opts
      |> Keyword.put(:name, :rpc_name)
      |> Keyword.put(:handler, :node_name)
      |> Keyword.put(:net, {netmod, :network_name})

    children = [
      # FIXME: only instantiate a UDP network (Fake lives outside!)
      {netmod, net_opts},
      {ScaleGraph.RPC, rpc_opts},
      {ScaleGraph.Node, node_opts},
    ]

    Supervisor.init(children, opts)
  end

end
