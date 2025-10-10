defmodule ScaleGraph.Daemon.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, args) do
    Logger.info("starting #{__MODULE__} using NodeSupervisor")
    Logger.info("args: #{inspect(args)}")
    keys = Crypto.generate_keys()
    id = Util.key_to_id(keys.pub)
    addr = {{127, 1, 1, 1}, 9001}

    opts = [
      keys: keys, id: id, addr: addr,
      strategy: :one_for_one,
      name: ScaleGraph.Daemon.NodeSupervisor
    ]
    children = [
      {ScaleGraph.NodeSupervisor, opts}
    ]

    opts = [strategy: :one_for_one, name: ScaleGraph.Daemon.Supervisor]
    Supervisor.start_link(children, opts)
  end

end
