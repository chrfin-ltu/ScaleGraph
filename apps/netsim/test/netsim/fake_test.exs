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

  test "should not crash when sending to bogus address" do
    import ExUnit.CaptureLog
    {:ok, net} = Netsim.Fake.start_link([])
    :ok = Netsim.Fake.connect(net, {{127, 0, 0, 1}, 12345}, self())

    # This one fails...
    assert capture_log(fn ->
      Netsim.Fake.send(net, {{127, 127, 127, 127}, 0}, "hello")
      :timer.sleep(50)
    end) =~ "destination temporarily down?"

    # ...but this one should still succeed!
    Netsim.Fake.send(net, {{127, 0, 0, 1}, 12345}, "world")
    assert_receive {:network, "world"}
  end
end
