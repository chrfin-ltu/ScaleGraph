defmodule ScaleGraph.DHT.ContactTest do
  use ExUnit.Case
  alias ScaleGraph.DHT.Contact

  setup do
    %{
      id: 1234,
      addr: {{192, 168, 17, 1}, 4321},
      rtt: 100
    }
  end

  test "contact with id and addr", %{id: id, addr: addr, rtt: rtt} do
    contact = Contact.new(id, addr, rtt)
    assert contact.id == id
    assert contact.addr == addr
    assert contact.rtt == rtt
  end

  test "contact to pair", %{id: id, addr: addr} do
    contact = Contact.new(id, addr, nil)
    assert Contact.pair(contact) == {id, addr}
  end

  test "update address", %{id: id, addr: addr, rtt: rtt} do
    contact = Contact.new(id, addr, rtt)
    addr2 = {{127, 0, 1, 2}, 2345}
    contact = Contact.addr(contact, addr2)
    assert contact.id == id
    assert contact.addr == addr2
    assert contact.rtt == rtt
  end

  test "update rtt starting with nil", %{id: id, addr: addr} do
    contact = Contact.new(id, addr, nil)
    contact = Contact.rtt(contact, 300)
    assert contact.id == id
    assert contact.addr == addr
    assert contact.rtt == 300
  end

  test "update rtt starting with 100", %{id: id, addr: addr} do
    contact = Contact.new(id, addr, 100)
    contact = Contact.rtt(contact, 300)
    assert contact.id == id
    assert contact.addr == addr
    assert contact.rtt == (100 + 300) / 2
  end

  test "update with contact", %{id: id, addr: addr} do
    contact = Contact.new(id, addr, 100)
    addr2 = {{127, 0, 1, 2}, 2345}
    new = Contact.new(id, addr2, 200)
    contact = Contact.update(contact, new)
    assert contact.id == id
    assert contact.addr == addr2
    assert contact.rtt == (100 + 200) / 2
  end

  test "updating nil contact", %{id: id, addr: addr, rtt: rtt} do
    new = Contact.new(id, addr, rtt)
    contact = Contact.update(nil, new)
    assert contact.id == id
    assert contact.addr == addr
    assert contact.rtt == rtt
  end

end
