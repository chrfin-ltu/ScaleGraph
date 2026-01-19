defmodule ScaleGraph.Consensus.Instance do
  def process_tx(instance, {tx, sig}) do
    GenServer.cast(instance, {:process_tx, {tx, sig}})
  end
end
