defmodule ScaleGraph.Sim.Application do
  use Application
  require Logger

  # Starts a global registry/directory where each simulation can register a
  # registry for its processes (node supervisors and such).
  @impl Application
  def start(_type, _args) do
    Logger.info("starting #{inspect __MODULE__}")

    children = [
      {Registry, [keys: :unique, name: regdir_name()]},
    ]
    opts = [strategy: :one_for_one, name: __MODULE__]
    Supervisor.start_link(children, opts)
  end

  @doc false
  def regdir_name(), do: ScaleGraph.Sim.RegDir

end
