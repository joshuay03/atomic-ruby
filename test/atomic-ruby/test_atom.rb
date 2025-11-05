# frozen_string_literal: true

require "test_helper"

class TestAtom < Minitest::Test
  def test_init
    atom = Atom.new(0)
    assert_equal 0, atom.value
  end

  if AtomicRuby::RACTOR_SAFE
    def test_atom_shareable
      atom = Atom.new(proc { })
      assert Ractor.shareable?(atom)
    end

    def test_value_not_shareable_in_same_ractor
      atom = Atom.new(proc { })
      refute Ractor.shareable?(atom.value)
    end

    def test_value_non_shareable_cross_ractor_raises
      atom = Atom.new(Object.new)
      error = assert_raises Ractor::RemoteError do
        Ractor.new(atom) do |atom|
          Thread.current.report_on_exception = false

          atom.value
        end.value
      end
      assert_kind_of ArgumentError, error.cause
    end

    def test_value_shareable_cross_ractor
      atom = Atom.new(42)
      result = Ractor.new(atom) { |atom| atom.value }.value
      assert_equal 42, result
    end
  end

  def test_swap_with_immutable_value
    atom = Atom.new(0)
    atom.swap { |current_value| current_value + 1 }
    assert_equal 1, atom.value
    atom.swap { |current_value| current_value + 1 }
    assert_equal 2, atom.value
  end

  def test_swap_with_non_mutating_operation
    array = []
    atom = Atom.new(array)
    atom.swap do |current_value|
      current_value + [1]
    end
    assert_equal [1], atom.value
    refute_equal array, (new_array = atom.value)
    atom.swap do |current_value|
      current_value + [2]
    end
    assert_equal [1, 2], atom.value
    refute_equal new_array, atom.value
  end

  def test_swap_with_mutating_operation
    array = []
    atom = Atom.new(array)
    atom.swap do |current_value|
      current_value << 1
      current_value
    end
    assert_equal [1], atom.value
    assert_equal array, atom.value
    atom.swap do |current_value|
      current_value << 2
      current_value
    end
    assert_equal [1, 2], atom.value
    assert_equal array, atom.value
  end

  if AtomicRuby::RACTOR_SAFE
    def test_swap_immutable_value_cross_ractor
      atom = Atom.new(0)
      10.times.map do
        Ractor.new(atom) do |atom|
          atom.swap { |current_value| current_value + 1 }
        end
      end.each(&:value)
      assert_equal 10, atom.value
    end

    def test_swap_non_mutating_operation_cross_ractor
      atom = Atom.new([])
      10.times.map do
        Ractor.new(atom) do |atom|
          atom.swap do |current_value|
            current_value + [current_value.length + 1]
          end
        end
      end.each(&:value)
      assert_equal (1..10).to_a, atom.value.sort
    end

    def test_swap_non_shareable_proc_cross_ractor_raises
      atom = Atom.new(0)
      error = assert_raises Ractor::RemoteError do
        Ractor.new(atom) do |atom|
          Thread.current.report_on_exception = false

          atom.swap { Object.new.instance_exec { proc { } } }
        end.value
      end
      assert_kind_of Ractor::IsolationError, error.cause
    end
  end
end
