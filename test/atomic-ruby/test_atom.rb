# frozen_string_literal: true

require "test_helper"

class TestAtom < Minitest::Test
  def test_swap_and_value
    atom = AtomicRuby::Atom.new(0)
    assert_equal 0, atom.value
    atom.swap { |current| current + 1 }
    assert_equal 1, atom.value
    atom.swap { |current| current + 1 }
    assert_equal 2, atom.value
  end
end
