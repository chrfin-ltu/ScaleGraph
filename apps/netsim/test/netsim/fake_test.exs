defmodule Netsim.FakeTest do
  use ExUnit.Case

  test "connect, send, receive" do
    {:ok, net} = Netsim.Fake.start_link([])
    :ok = Netsim.Fake.connect(net, {{127, 0, 0, 1}, 12345}, self())

    spawn(fn ->
      Netsim.Fake.send(net, {{127, 0, 0, 1}, 12345}, "hello")
    end)

    assert_receive {:network, "hello"}
  end

  test "connect with inferred PID" do
    {:ok, net} = Netsim.Fake.start_link([])
    :ok = Netsim.Fake.connect(net, {{127, 0, 0, 1}, 12345})

    spawn(fn ->
      Netsim.Fake.send(net, {{127, 0, 0, 1}, 12345}, "hello")
    end)

    assert_receive {:network, "hello"}
  end

  @tag skip: "TODO"
  test "should not crash when sending to bogus address" do
    {:ok, net} = Netsim.Fake.start_link([])
    :ok = Netsim.Fake.connect(net, {{127, 0, 0, 1}, 12345}, self())

    spawn(fn ->
      Netsim.Fake.send(net, {{127, 127, 127, 127}, 0}, "hello")
      Netsim.Fake.send(net, {{127, 0, 0, 1}, 12345}, "world")
    end)

    assert_receive {:network, "world"}
  end
end
