defmodule ScaleGraph.Daemon.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    keys = Crypto.generate_keys()
    id = Util.key_to_id(keys.priv)
    addr = {{127, 0, 0, 1}, 9001}

    children = [
      # Starts a worker by calling: ScaleGraph.Daemon.Worker.start_link(arg)
      # {ScaleGraph.Daemon.Worker, arg}
      {Netsim.Fake, [name: :network]},
      {ScaleGraph.RPC,
       [name: :rpc, id: id, addr: addr, net: {Netsim.Fake, :network}, handler: :node]},
      {ScaleGraph.Node, [name: :node, rpc: :rpc]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ScaleGraph.Daemon.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
