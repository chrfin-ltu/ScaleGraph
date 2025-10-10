defmodule Netsim.UDPTest do
  use ExUnit.Case
  alias Netsim.UDP

  # Since the tests open real ports, pick a "random" address and port that is
  # unlikely to be in use.
  @bind_port 24680
  @bind_ip {127, 159, 246, 123}
  @bind_addr {@bind_ip, @bind_port}

  test "start, connect, send to self" do
    {:ok, udp} = UDP.start_link([])
    UDP.connect(udp, @bind_addr)
    # Sending to self
    UDP.send(udp, @bind_addr, "hello")
    assert_receive {:network, "hello"}
  end

  test "with registry and via tuple" do
    Registry.start_link(keys: :unique, name: __MODULE__)
    key = {@bind_addr, :owner}
    owner_via = {:via, Registry, {__MODULE__, key}}
    {:ok, udp} = UDP.start_link([])
    this = self()

    spawn(fn ->
      Registry.register(__MODULE__, key, nil)
      UDP.connect(udp, @bind_addr, owner_via)
      UDP.send(udp, @bind_addr, "hello")
      assert_receive {:network, "hello"}
      send(this, "done")
    end)

    assert_receive "done"
  end

end
