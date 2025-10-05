defmodule ScaleGraph.DaemonTest do
  use ExUnit.Case
  doctest ScaleGraph.Daemon

  test "greets the world" do
    assert ScaleGraph.Daemon.hello() == :world
  end
end
