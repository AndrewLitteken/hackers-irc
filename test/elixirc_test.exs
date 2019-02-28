defmodule ElixircTest do
  use ExUnit.Case
  doctest Elixirc

  test "greets the world" do
    assert Elixirc.hello() == :world
  end
end
