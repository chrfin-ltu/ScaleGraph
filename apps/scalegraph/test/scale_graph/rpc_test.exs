defmodule ScaleGraph.RPCTest do
  use ExUnit.Case
  alias Netsim.Fake
  alias ScaleGraph.RPC

  # TODO: might want to refactor some of these tests into a common setup.

  test "send ping" do
    {:ok, net} = Fake.start_link([])
    addr1 = {{127, 0, 0, 1}, 12345}
    addr2 = {{127, 0, 0, 2}, 23456}

    {:ok, rpc1} =
      RPC.start_link(
        addr: addr1,
        id: 123,
        net: net
      )

    {:ok, rpc2} =
      RPC.start_link(
        addr: addr2,
        id: 234,
        net: net
      )

    RPC.ping(rpc1, addr2)
    assert_receive {:rpc_request, {:ping, {addr1, addr2, nil, _id}}} = request
    RPC.ping(rpc2, addr1)
    assert_receive {:rpc_request, {:ping, {addr2, addr1, nil, _id}}}
  end

  test "ping pong" do
    {:ok, net} = Fake.start_link([])
    addr1 = {{127, 0, 0, 1}, 12345}
    addr2 = {{127, 0, 0, 2}, 23456}

    {:ok, rpc1} =
      RPC.start_link(
        addr: addr1,
        id: 123,
        net: net
      )

    {:ok, rpc2} =
      RPC.start_link(
        addr: addr2,
        id: 234,
        net: net
      )

    RPC.ping(rpc1, addr2)
    assert_receive {:rpc_request, {:ping, {^addr1, ^addr2, nil, id}}} = request
    RPC.respond(rpc2, request, nil)
    assert_receive {:rpc_response, {:ping, {^addr2, ^addr1, nil, ^id}}}
  end

  test "find nodes request and response" do
    {:ok, net} = Fake.start_link([])
    addr1 = {{127, 0, 0, 1}, 12345}
    addr2 = {{127, 0, 0, 2}, 23456}

    {:ok, rpc1} =
      RPC.start_link(
        addr: addr1,
        id: 123,
        net: net
      )

    {:ok, rpc2} =
      RPC.start_link(
        addr: addr2,
        id: 234,
        net: net
      )

    RPC.find_nodes(rpc1, addr2, 54321)
    assert_receive {:rpc_request, {:find_nodes, {^addr1, ^addr2, 54321, id}}} = request
    closest = [{234, addr2}]
    RPC.respond(rpc2, request, closest)
    assert_receive {:rpc_response, {:find_nodes, {^addr2, ^addr1, ^closest, ^id}}}
  end
end
