# frozen_string_literal: true

require "test_helper"

class TestAtom < Minitest::Test
  def test_init
    atom = Atom.new(0)
    assert_equal 0, atom.value
  end

  if AtomicRuby::RACTOR_SAFE
    def test_shareable
      atom = Atom.new(0)
      assert Ractor.shareable?(atom)
    end

    def test_not_shareable_init
      assert_raises Ractor::IsolationError do
        Atom.new(proc { })
      end
    end

    def test_shareable_init
      proc = Ractor.shareable_proc { }
      atom = Atom.new(proc)
      assert_equal proc, atom.value
    end
  end

  def test_swap
    atom = Atom.new(0)
    atom.swap { |current_value| current_value + 1 }
    assert_equal 1, atom.value
    atom.swap { |current_value| current_value + 1 }
    assert_equal 2, atom.value
  end

  if AtomicRuby::RACTOR_SAFE
    def test_swap_in_ractor
      atom = Atom.new(0)
      ractors = 10.times.map do
        Ractor.new(atom) do |shared_atom|
          shared_atom.swap { |current| current + 1 }
        end
      end
      ractors.each(&:value)
      assert_equal 10, atom.value
    end
  end
end
