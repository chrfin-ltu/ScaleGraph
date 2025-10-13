# TODO:
# - init_production and init_simulation currently expect different options
#   (or rather expect options in different shapes). The two cases should be
#   unified so that there is less special-casing.
# - Always take names from the outside as options and fall back on defaults.
defmodule ScaleGraph.NodeSupervisor do
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, opts)
  end

  @impl Supervisor
  def init(opts) do
    # TODO: should be able to infer mode from options and
    # massage them appropriately.
    case opts[:mode] do
      :production -> init_production(opts)
      :simulation -> init_simulation(opts)
    end
  end

  defp init_production(opts) do
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

  defp init_simulation(opts) do
    node_opts = opts[:node_opts]
    net_opts = opts[:net_opts]
    rpc_opts = opts[:rpc_opts]

    children = [
      {ScaleGraph.RPC, rpc_opts},
      {ScaleGraph.Node, node_opts},
    ]

    children =
      if net_opts == nil do
        children
      else
        [{net_opts[:mod], net_opts} | children]
      end

    Supervisor.init(children, opts)
  end

end
