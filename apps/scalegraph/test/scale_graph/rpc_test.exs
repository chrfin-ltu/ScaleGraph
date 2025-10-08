defmodule ScaleGraph.RPCTest do
  use ExUnit.Case
  alias Netsim.Fake
  alias Netsim.UDP
  alias ScaleGraph.RPC

  # TODO: might want to refactor some of these tests into a common setup.

  describe "with fake network" do
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


    test "send ping", context do
      %{addr1: addr1, addr2: addr2, rpc1: rpc1, rpc2: rpc2} = context
      RPC.ping(rpc1, addr2)
      assert_receive {:rpc_request, {:ping, {^addr1, ^addr2, nil, _id}}}
      RPC.ping(rpc2, addr1)
      assert_receive {:rpc_request, {:ping, {^addr2, ^addr1, nil, _id}}}
    end


    test "ping pong", context do
      %{addr1: addr1, addr2: addr2, rpc1: rpc1, rpc2: rpc2} = context
      RPC.ping(rpc1, addr2)
      assert_receive {:rpc_request, {:ping, {^addr1, ^addr2, nil, id}}} = req
      RPC.respond(rpc2, req, nil)
      assert_receive {:rpc_response, {:ping, {^addr2, ^addr1, nil, ^id}}}
    end


    # The response to a request is delivered to the sender (not necessarily the
    # handler process).
    test "response is delivered to caller", context do
      %{addr1: addr1, addr2: addr2, rpc1: rpc1, rpc2: rpc2} = context
      parent = self()
      spawn(fn ->
        RPC.ping(rpc1, addr2)
        assert_receive {:rpc_response, {:ping, {^addr2, ^addr1, nil, _id}}}
        send(parent, "done")
      end)
      assert_receive {:rpc_request, {:ping, {^addr1, ^addr2, nil, _id}}} = req
      RPC.respond(rpc2, req, nil)
      assert_receive "done"
    end


    # Responses can also be delivered to a designated receiver instead of
    # the sender.
    test "response delivered to specified process", context do
      %{addr1: addr1, addr2: addr2, rpc1: rpc1, rpc2: rpc2} = context
      parent = self()
      receiver = spawn(fn ->
        assert_receive {:rpc_response, {:ping, {^addr2, ^addr1, nil, _id}}}
        send(parent, "done")
      end)
      RPC.ping(rpc1, addr2, reply_to: receiver)
      assert_receive {:rpc_request, {:ping, {^addr1, ^addr2, nil, _id}}} = req
      RPC.respond(rpc2, req, nil)
      assert_receive "done"
    end


    test "unexpected response is logged and delivered to handler", context do
      import ExUnit.CaptureLog
      %{addr1: addr1, addr2: addr2, rpc1: rpc1} = context
      id = 12321
      req = {:rpc_request, {:ping, {addr1, addr2, nil, id}}}
      assert capture_log(fn ->
        RPC.respond(rpc1, req, nil)
        assert_receive {:rpc_response, {:ping, {^addr2, ^addr1, nil, ^id}}}
      end) =~ "orphan RPC response"
    end


    test "find nodes request and response", context do
      %{addr1: addr1, addr2: addr2, rpc1: rpc1, rpc2: rpc2} = context
      RPC.find_nodes(rpc1, addr2, 54321)
      assert_receive {:rpc_request, {:find_nodes, {^addr1, ^addr2, 54321, id}}} = req
      closest = [{234, addr2}]
      RPC.respond(rpc2, req, closest)
      assert_receive {:rpc_response, {:find_nodes, {^addr2, ^addr1, ^closest, ^id}}}
    end
  end

  test "UDP ping pong" do
    {:ok, net1} = UDP.start_link([])
    addr1 = {{127, 0, 0, 1}, 12345}
    {:ok, net2} = UDP.start_link([])
    addr2 = {{127, 0, 0, 2}, 23456}

    {:ok, rpc1} =
      RPC.start_link(
        addr: addr1,
        id: 123,
        net: {UDP, net1}
      )

    {:ok, rpc2} =
      RPC.start_link(
        addr: addr2,
        id: 234,
        net: {UDP, net2}
      )

    RPC.ping(rpc1, addr2)
    assert_receive {:rpc_request, {:ping, {^addr1, ^addr2, nil, id}}} = request
    RPC.respond(rpc2, request, nil)
    assert_receive {:rpc_response, {:ping, {^addr2, ^addr1, nil, ^id}}}
  end
end
