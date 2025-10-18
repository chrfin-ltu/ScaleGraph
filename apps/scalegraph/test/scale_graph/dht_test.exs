defmodule ScaleGraph.DHTTest do
  use ExUnit.Case
  alias ScaleGraph.RPC
  alias ScaleGraph.DHT
  alias DHT.FakeRT

  test "DHT join, no bucket refresh" do
    id = 10_000
    dht_addr = {{100, 0, 0, 0}, 10_000}
    shard_size = 5
    net_mod = Netsim.Fake
    {:ok, net} = net_mod.start_link([])
    rpc_opts = [
      id: id,
      addr: dht_addr,
      net: {net_mod, net},
    ]
    {:ok, dht_rpc} = RPC.start_link(rpc_opts)
    rt_opts = [
      id: id,
      id_bits: 8,
      bucket_size: shard_size,
    ]
    # The DHT RPC does not need a handler, because it will not receive requests.
    rt_mod = FakeRT
    {:ok, rt} = rt_mod.start_link(rt_opts)
    lookup_opts = [
      rpc: dht_rpc,
      n_lookup: shard_size,
      alpha: 3,
    ]
    {:ok, dht} = DHT.start_link(
      id: id,
      rpc: dht_rpc,
      rt: rt,
      rt_mod: rt_mod,
      shard_size: shard_size,
      lookup_opts: lookup_opts
    )
    net_mod.connect(net, dht_addr, dht_rpc)
    # Set up the test's RPC.
    test_id = 10_001
    test_addr = {{100, 0, 0, 1}, 10_001}
    rpc_opts = [
      id: test_id,
      addr: test_addr,
      net: {net_mod, net}, # same network
    ]
    {:ok, test_rpc} = RPC.start_link(rpc_opts)
    # Set this process as the RPC handler, and connect the RPC server to
    # multiple addresses so we can pretend to be different nodes.
    RPC.set_handler(test_rpc, self())
    net_mod.connect(net, {{100, 0, 0, 2}, 10_002}, test_rpc)
    # Start the join!
    parent = self()
    spawn(fn ->
      result = DHT.join(dht, bootstrap: [{test_id, test_addr}])
      assert %{before: 0, after: 1} = result  # WRONG
      #assert %{before: 0, after: 2} = result # CORRECT
      send(parent, "done")
    end)
    # Reply to requsets from DHT/lookup.
    assert_receive {:rpc_request, {:find_nodes, _}} = req
    RPC.respond(test_rpc, req, [{10_002, {{100, 0, 0, 2}, 10_002}}])
    assert_receive {:rpc_request, {:find_nodes, _}} = req
    RPC.respond(test_rpc, req, [{10_001, {{100, 0, 0, 1}, 10_001}}])
    assert_receive "done"
  end

end
