defmodule AgainTest do
  use ExUnit.Case
  doctest Again

  test "greets the world" do
    assert Again.hello() == :world
  end
end
