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
          net: {Fake, net},
          handler: self()
        )

      {:ok, rpc2} =
        RPC.start_link(
          addr: addr2,
          id: 234,
          net: {Fake, net},
          handler: self()
        )

      %{id1: 123, id2: 234, addr1: addr1, addr2: addr2, rpc1: rpc1, rpc2: rpc2}
    end


    test "send ping", context do
      %{id1: id1, id2: id2} = context
      %{addr1: addr1, addr2: addr2, rpc1: rpc1, rpc2: rpc2} = context
      src = {id1, addr1}
      dst = {id2, addr2}
      RPC.ping(rpc1, dst)
      assert_receive {:rpc_request, {:ping, {^src, ^dst, nil, _id}}} = req
      assert RPC.src(req) == src
      assert RPC.dst(req) == dst
      src = {id2, addr2}
      dst = {id1, addr1}
      RPC.ping(rpc2, dst)
      assert_receive {:rpc_request, {:ping, {^src, ^dst, nil, _id}}} = req
      assert RPC.src(req) == src
      assert RPC.dst(req) == dst
    end


    test "ping pong", context do
      %{id1: id1, id2: id2} = context
      %{addr1: addr1, addr2: addr2, rpc1: rpc1, rpc2: rpc2} = context
      src = {id1, addr1}
      dst = {id2, addr2}
      RPC.ping(rpc1, dst)
      assert_receive {:rpc_request, {:ping, {^src, ^dst, nil, id}}} = req
      RPC.respond(rpc2, req, nil)
      assert_receive {:rpc_response, {:ping, {^dst, ^src, nil, ^id}}}
    end


    # The response to a request is delivered to the sender (not necessarily the
    # handler process).
    test "response is delivered to caller", context do
      %{id1: id1, id2: id2} = context
      %{addr1: addr1, addr2: addr2, rpc1: rpc1, rpc2: rpc2} = context
      parent = self()
      src = {id1, addr1}
      dst = {id2, addr2}
      spawn(fn ->
        RPC.ping(rpc1, dst)
        assert_receive {:rpc_response, {:ping, {^dst, ^src, nil, _id}}}
        send(parent, "done")
      end)
      assert_receive {:rpc_request, {:ping, {^src, ^dst, nil, _id}}} = req
      RPC.respond(rpc2, req, nil)
      assert_receive "done"
    end


    # Responses can also be delivered to a designated receiver instead of
    # the sender.
    test "response delivered to specified process", context do
      %{id1: id1, id2: id2} = context
      %{addr1: addr1, addr2: addr2, rpc1: rpc1, rpc2: rpc2} = context
      parent = self()
      src = {id1, addr1}
      dst = {id2, addr2}
      receiver = spawn(fn ->
        assert_receive {:rpc_response, {:ping, {^dst, ^src, nil, _id}}}
        send(parent, "done")
      end)
      RPC.ping(rpc1, dst, reply_to: receiver)
      assert_receive {:rpc_request, {:ping, {^src, ^dst, nil, _id}}} = req
      RPC.respond(rpc2, req, nil)
      assert_receive "done"
    end


    test "unexpected response is logged but not delivered to handler", context do
      import ExUnit.CaptureLog
      %{id1: id1, id2: id2} = context
      %{addr1: addr1, addr2: addr2, rpc1: rpc1} = context
      src = {id1, addr1}
      dst = {id2, addr2}
      id = 12321
      req = {:rpc_request, {:ping, {src, dst, nil, id}}}
      assert capture_log(fn ->
        RPC.respond(rpc1, req, nil)
        :timer.sleep(50)
      end) =~ "orphan RPC response"
    end


    test "find nodes request and response", context do
      %{id1: id1, id2: id2} = context
      %{addr1: addr1, addr2: addr2, rpc1: rpc1, rpc2: rpc2} = context
      src = {id1, addr1}
      dst = {id2, addr2}
      RPC.find_nodes(rpc1, dst, 54321)
      assert_receive {:rpc_request, {:find_nodes, {^src, ^dst, 54321, id}}} = req
      closest = [{234, addr2}]
      RPC.respond(rpc2, req, closest)
      assert_receive {:rpc_response, {:find_nodes, {^dst, ^src, ^closest, ^id}}}
    end

    test "ping with timeout", context do
      %{id1: id1, id2: id2} = context
      %{addr1: addr1, addr2: addr2, rpc1: rpc1} = context
      src = {id1, addr1}
      dst = {id2, addr2}
      RPC.ping(rpc1, dst, timeout: 50)
      assert_receive {:rpc_request, {:ping, {^src, ^dst, nil, _id}}} = req
      # Don't respond. Eventually we get a timeout.
      assert_receive {:timeout, ^req}
    end

    test "ping with timeout and late response", context do
      import ExUnit.CaptureLog
      %{id1: id1, id2: id2} = context
      %{addr1: addr1, addr2: addr2, rpc1: rpc1, rpc2: rpc2} = context
      src = {id1, addr1}
      dst = {id2, addr2}
      RPC.ping(rpc1, dst, timeout: 50)
      assert_receive {:rpc_request, {:ping, {^src, ^dst, nil, _id}}} = req
      # Don't respond. Eventually we get a timeout.
      assert_receive {:timeout, ^req}
      assert capture_log(fn ->
        RPC.respond(rpc2, req, nil)
        :timer.sleep(50)
      end) =~ "orphan RPC response"
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
        net: {UDP, net1},
        handler: self()
      )

    {:ok, rpc2} =
      RPC.start_link(
        addr: addr2,
        id: 234,
        net: {UDP, net2},
        handler: self()
      )
    src = {123, addr1}
    dst = {234, addr2}

    RPC.ping(rpc1, dst)
    assert_receive {:rpc_request, {:ping, {^src, ^dst, nil, id}}} = request
    RPC.respond(rpc2, request, nil)
    assert_receive {:rpc_response, {:ping, {^dst, ^src, nil, ^id}}}
  end

end
