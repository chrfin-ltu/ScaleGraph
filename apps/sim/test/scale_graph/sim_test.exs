defmodule SimTest do
  use ExUnit.Case
  alias ScaleGraph.Sim

  setup do
    Application.ensure_all_started(:sim)
    :ok
  end

  # Sim.App --> Reg
  # Sim --> DynamicSupervisor --> [Fake, *NodeSupervisor]

  test "sim with node count 10" do
    node_count = 10
    {:ok, sim} = Sim.start_link(node_count: node_count)
    state = :sys.get_state(sim)
    supervisor = state.supervisor

    # Check supervisor children
    node_supervisors = DynamicSupervisor.which_children(supervisor)
    assert length(node_supervisors) == node_count + 1
    child_count = DynamicSupervisor.count_children(supervisor)
    assert child_count.specs == node_count + 1
    assert child_count.active == node_count + 1
    assert child_count.supervisors == node_count
    assert child_count.workers == 1
    # Check that nodes and node supervisors are up
    Enum.each(state.node_names, fn name ->
      assert Process.alive?(GenServer.whereis(name))
    end)
    Enum.each(state.node_supers, fn name ->
      assert Process.alive?(GenServer.whereis(name))
    end)
    # Can ping
    bogus_id = 123
    dst = {bogus_id, {{127, 54, 54, 1}, 54321}}
    Enum.each(state.node_names, fn node_name ->
      result = ScaleGraph.Node.ping(node_name, dst)
      assert {:rpc_response, {:ping, _}} = result
    end)

    # --- Stopping a Node ---
    # It is restarted by the NodeSupervisor. So nothing changes.
    GenServer.stop(Enum.at(state.node_names, 0))
    :timer.sleep(10)  # TODO: Figure out how not to need this.
    # Check supervisor children
    node_supervisors = DynamicSupervisor.which_children(supervisor)
    assert length(node_supervisors) == node_count + 1
    child_count = DynamicSupervisor.count_children(supervisor)
    assert child_count.specs == node_count + 1
    assert child_count.active == node_count + 1
    assert child_count.supervisors == node_count
    assert child_count.workers == 1
    # Check that nodes and node supervisors are still up
    Enum.each(state.node_names, fn name ->
      assert Process.alive?(GenServer.whereis(name))
    end)
    Enum.each(state.node_supers, fn name ->
      assert Process.alive?(GenServer.whereis(name))
    end)
    # Can still ping
    bogus_id = 123
    dst = {bogus_id, {{127, 54, 54, 1}, 54321}}
    Enum.each(state.node_names, fn node_name ->
      result = ScaleGraph.Node.ping(node_name, dst)
      assert {:rpc_response, {:ping, _}} = result
    end)

    # --- Stopping a NodeSupervisor ---
    # This changes nothing, because it will be restarted by the
    # DynamicSupervisor. It is not clear that we want this.
    # We may want to be able to permanently take down a whole
    # node.
    GenServer.stop(Enum.at(state.node_supers, 1))
    :timer.sleep(10)  # TODO: Figure out how not to need this.
    # Check supervisor children
    node_supervisors = DynamicSupervisor.which_children(supervisor)
    assert length(node_supervisors) == node_count + 1
    child_count = DynamicSupervisor.count_children(supervisor)
    assert child_count.specs == node_count + 1
    assert child_count.active == node_count + 1
    assert child_count.supervisors == node_count
    assert child_count.workers == 1
    # Check that nodes and node supervisors are still up
    Enum.each(state.node_names, fn name ->
      assert Process.alive?(GenServer.whereis(name))
    end)
    Enum.each(state.node_supers, fn name ->
      assert Process.alive?(GenServer.whereis(name))
    end)
    # Can still ping
    bogus_id = 123
    dst = {bogus_id, {{127, 54, 54, 1}, 54321}}
    Enum.each(state.node_names, fn node_name ->
      result = ScaleGraph.Node.ping(node_name, dst)
      assert {:rpc_response, {:ping, _}} = result
    end)

    # Remember PIDs so we can check that the processes are down.
    node_pids = Enum.map(state.node_names, &GenServer.whereis/1)
    node_super_pids = Enum.map(state.node_supers, &GenServer.whereis/1)

    # --- Stopping the simulation ---
    # Now everything is taken down.
    GenServer.stop(sim)
    :timer.sleep(10)  # TODO: Figure out how not to need this.
    assert not Process.alive?(sim)
    assert GenServer.whereis(supervisor) == nil
    assert GenServer.whereis(state.network) == nil
    Enum.each(state.node_names, fn name ->
      assert GenServer.whereis(name) == nil
    end)
    Enum.each(state.node_supers, fn name ->
      assert GenServer.whereis(name) == nil
    end)
    Enum.each(node_pids, fn pid ->
      assert not Process.alive?(pid)
    end)
    Enum.each(node_super_pids, fn pid ->
      assert not Process.alive?(pid)
    end)
  end

  test "kill node" do
    node_count = 5
    {:ok, sim} = Sim.start_link(node_count: node_count)
    state = :sys.get_state(sim)
    supervisor = state.supervisor
    # before
    child_counts = DynamicSupervisor.count_children(supervisor)
    assert %{specs: 6, active: 6, supervisors: 5, workers: 1} = child_counts
    # kill
    pid = Sim.node_pid(sim, {{127, 54, 54, 1}, 54321})
    Sim.kill_node(sim, {{127, 54, 54, 1}, 54321})
    # after
    child_counts = DynamicSupervisor.count_children(supervisor)
    assert %{specs: 5, active: 5, supervisors: 4, workers: 1} = child_counts
    assert not Process.alive?(pid)
  end

  test "crash and restart node" do
    node_count = 5
    {:ok, sim} = Sim.start_link(node_count: node_count)
    state = :sys.get_state(sim)
    supervisor = state.supervisor
    # before
    child_counts = DynamicSupervisor.count_children(supervisor)
    assert %{specs: 6, active: 6, supervisors: 5, workers: 1} = child_counts
    # kill
    pid = Sim.node_pid(sim, {{127, 54, 54, 1}, 54321})
    Sim.crash_node(sim, {{127, 54, 54, 1}, 54321})
    # after
    child_counts = DynamicSupervisor.count_children(supervisor)
    assert %{specs: 6, active: 6, supervisors: 5, workers: 1} = child_counts
    assert not Process.alive?(pid)
    :timer.sleep(10)
    new_pid = Sim.node_pid(sim, {{127, 54, 54, 1}, 54321})
    assert pid != new_pid
    assert Process.alive?(new_pid)
  end

  test "joining" do
    node_count = 5
    {:ok, sim} = Sim.start_link(node_count: node_count)
    state = :sys.get_state(sim)
    Sim.join(sim, [])
    Enum.each(state.node_names, fn node ->
      node_state = :sys.get_state(node)
      dht_state = :sys.get_state(node_state.dht)
      rt = dht_state.rt
      rt_mod = dht_state.rt_mod
      assert rt_mod.size(rt) == node_count - 1
    end)
  end

end
