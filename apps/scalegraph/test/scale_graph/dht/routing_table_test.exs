defmodule ScaleGraph.DHT.RoutingTableTest do
  use ExUnit.Case
  alias ScaleGraph.DHT.Contact
  alias ScaleGraph.DHT.FakeRT

  setup context do
    id = Map.get(context, :id, 0)
    id_bits = Map.get(context, :id_bits, 4)
    bucket_size = Map.get(context, :bucket_size, 5)
    # When we implement real RTs, change the default here.
    rt_mod = Map.get(context, :rt_mod, FakeRT)
    ncontacts = Map.get(context, :ncontacts, 10)
    opts = [
      id: id,
      id_bits: id_bits,
      bucket_size: bucket_size,
    ]
    {:ok, rt} = rt_mod.start_link(opts)
    contacts = Enum.map(1..ncontacts, fn i ->
      Contact.new(i, {{127, 0, 0, i}, 10_000 + i}, nil)
    end)
    nodes = Enum.map(1..ncontacts, fn i ->
      {i, {{127, 0, 0, i}, 10_000 + i}}
    end)
    %{
      id: id,
      id_bits: id_bits,
      bucket_size: bucket_size,
      rt_mod: rt_mod,
      rt: rt,
      opts: opts,
      contacts: contacts,
      nodes: nodes,
    }
  end

  @tag id: 100
  @tag id_bits: 7
  @tag bucket_size: 10
  test "setup", context do
    assert context[:id] == 100
    assert context[:id_bits] == 7
    assert context[:bucket_size] == 10
    assert context[:rt_mod] == FakeRT
    assert length(context[:contacts]) == 10
    assert length(context[:nodes]) == 10
  end

  test "size and closest from empty RT", context do
    %{rt: rt, rt_mod: rt_mod, id: id} = context
    assert rt_mod.size(rt) == 0
    assert rt_mod.closest(rt, id) == []
  end

  test "update 1 and closest", context do
    %{rt: rt, rt_mod: rt_mod, id: id} = context
    contact = hd(context.contacts)
    rt_mod.update(rt, Contact.pair(contact))
    assert rt_mod.size(rt) == 1
    assert rt_mod.closest(rt, id) == [contact]
  end

  test "update all and closest", context do
    %{rt: rt, rt_mod: rt_mod, id: id} = context
    Enum.each(context.nodes, &rt_mod.update(rt, &1))
    assert rt_mod.size(rt) == 10
    expected = Enum.take(context.contacts, context.bucket_size)
    assert rt_mod.closest(rt, id) == expected
  end

  test "updating existing with rtt does not add", context do
    %{rt: rt, rt_mod: rt_mod, id: id} = context
    contact = hd(context.contacts)
    rt_mod.update(rt, Contact.pair(contact), 200)
    rt_mod.update(rt, Contact.pair(contact), 300)
    # Still only has one!
    assert rt_mod.size(rt) == 1
    [contact] = rt_mod.closest(rt, id)
    assert contact.rtt == (200 + 300) / 2
  end

  test "updating existing with address does not add", context do
    %{rt: rt, rt_mod: rt_mod, id: id} = context
    contact = hd(context.contacts)
    rt_mod.update(rt, Contact.pair(contact), 200)
    contact = Contact.addr(contact, {{192, 168, 100, 10}, 9999})
    rt_mod.update(rt, Contact.pair(contact), 300)
    # Still only has one!
    assert rt_mod.size(rt) == 1
    [contact] = rt_mod.closest(rt, id)
    assert contact.rtt == (200 + 300) / 2
    assert contact.addr == {{192, 168, 100, 10}, 9999}
  end

end
