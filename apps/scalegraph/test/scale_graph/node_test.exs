defmodule ScaleGraph.NodeTest do
  use ExUnit.Case
  alias Netsim.Fake
  alias ScaleGraph.RPC
  alias ScaleGraph.Node

  setup do
    {:ok, net} = Fake.start_link([])
    addr1 = {{127, 0, 0, 1}, 12345}
    addr2 = {{127, 0, 0, 2}, 23456}

    {:ok, rpc1} =
      RPC.start_link(
        addr: addr1,
        id: 123,
        net: {Fake, net}
      )

    {:ok, rpc2} =
      RPC.start_link(
        addr: addr2,
        id: 234,
        net: {Fake, net}
      )

    %{addr1: addr1, addr2: addr2, rpc1: rpc1, rpc2: rpc2}
  end

  test "pinging a node", context do
    %{addr1: addr1, addr2: addr2, rpc1: rpc1, rpc2: rpc2} = context
    {:ok, node1} = Node.start_link(rpc: rpc1)
    {:ok, node2} = Node.start_link(rpc: rpc2)
    resp = Node.ping(node1, addr2)
    assert {:rpc_response, {:ping, _}} = resp
  end

end
