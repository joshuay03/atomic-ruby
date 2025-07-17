# frozen_string_literal: true

require "test_helper"

class TestAtom < Minitest::Test
  def test_init
    atom = Atom.new(0)
    assert_equal 0, atom.value
  end

  def test_swap
    atom = Atom.new(0)
    atom.swap { |current_value| current_value + 1 }
    assert_equal 1, atom.value
    atom.swap { |current_value| current_value + 1 }
    assert_equal 2, atom.value
  end
end
