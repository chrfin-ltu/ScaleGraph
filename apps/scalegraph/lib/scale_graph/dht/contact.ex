# TODO: consider treating rtt=-1 as a special value that signals a dropped
# packet. But it might be better to specify drops explicitly!
defmodule ScaleGraph.DHT.Contact do
  @moduledoc """
  A contact holds information about other ScaleGraph nodes.

  A contact has an ID and an address (IP:port), but the defining feature is the
  ID. (The address could potentially change over time.)

  Currently, the only node connectivity metric that is tracked is RTT.
  The average RTT for a node is computed as an EMA with α = ½.
  """

  defstruct [
    id: nil,
    addr: nil,
    rtt: nil,
    # TODO: drops?
    # TODO: last_seen?
    # TODO: Maybe collect rtt, drops, last_seen (etc.) in a nested stats field?
  ]

  @doc """
  Make a new Contact with `id`, `addr` (`{ip, port}`).
  """
  def new(id, {_ip, _port} = addr, rtt \\ nil) do
    %__MODULE__{id: id, addr: addr, rtt: rtt}
  end

  @doc "Update the address of the contact."
  def addr(contact, addr) do
    Map.put(contact, :addr, addr)
  end

  @doc """
  Update an existing contact using new information about the contact.

  Updates the address and RTT. See `addr/2` and `rtt/2`.

  Assumes that `contact` is a known contact, with long-term info, and `new`
  holds new information about the same contact (i.e. with the same ID) that is
  to be integrated with the existing information.
  """
  def update(nil, %__MODULE__{} = new), do: new
  def update(contact, %__MODULE__{} = new) do
    contact
      |> addr(new.addr)
      |> rtt(new.rtt)
  end


  @doc "Update the RTT of the node using EMA. Passing `rtt = nil` is a no-op."
  def rtt(contact, rtt)
  def rtt(contact, nil), do: contact
  def rtt(contact, rtt) do
    if contact.rtt == nil do
      Map.put(contact, :rtt, rtt)
    else
      rtt = (contact.rtt + rtt) / 2
      Map.put(contact, :rtt, rtt)
    end
  end

  @doc "Convert to an `{id, addr}` pair."
  def pair(contact) do
    {contact.id, contact.addr}
  end

end
