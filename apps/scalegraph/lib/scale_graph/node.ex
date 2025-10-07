defmodule ScaleGraph.Node do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, opts)
  end

  @impl GenServer
  def init(_opts) do
    {:ok, nil}
  end
end
