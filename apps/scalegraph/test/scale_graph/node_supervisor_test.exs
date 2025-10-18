defmodule ScaleGraph.NodeSupervisorTest do
  use ExUnit.Case
  require Logger

  # Randomly kill some of the processes in the node supervision tree while
  # the node keeps pinging itself.
  test "chaos monkey" do
    keys = Crypto.generate_keys()
    id = Util.key_to_id(keys.pub)
    addr = {{127, 2, 2, 2}, 9002}
    opts = [
      mode: :production,
      keys: keys, id: id, addr: addr,
      shard_size: 5,
      # Need to allow many restarts!
      max_restarts: 500,
      max_seconds: 1,
      strategy: :one_for_one,
      name: __MODULE__
    ]
    ScaleGraph.NodeSupervisor.start_link(opts)

    parent = self()

    # Chaos monkey
    spawn_link(fn ->
      procs = [:network_name, :rpc_name, :node_name]
      Enum.each(1..100, fn _ ->
        proc = Enum.at(procs, Util.rand(2))
        try do
          Process.exit(Process.whereis(proc), :kill)
        rescue
          e -> Logger.error("#{inspect(e)}")
        end
        :timer.sleep(9)
      end)
      IO.puts("chaos monkey done")
      send(parent, "done")
    end)

    # PING-er
    spawn_link(fn ->
      Enum.each(1..500, fn i ->
        :timer.sleep(1)
        # This process will exit if ping times out. So we need to call ping in
        # a separate process to prevent the pinger from crashing.
        # Would be nice if the caller wouldn't exit/crash when a call times out!
        spawn(fn ->
          if rem(i, 50) == 0 do
            IO.puts("#{i}th ping (before)")
          end
          msg = ScaleGraph.Node.ping(:node_name, addr)
          assert {:rpc_response, {:ping, {^addr, ^addr, nil, _id}}} = msg
          if rem(i, 50) == 0 do
            IO.puts("#{i}th ping (after)")
          end
        end)
      end)
      IO.puts("pinger done")
      send(parent, "done")
    end)

    assert_receive "done", 2_000
    # Check that the application is still running
    assert {:error, _} = Application.start(:scalegraphd)
    assert_receive "done"
  end

end
