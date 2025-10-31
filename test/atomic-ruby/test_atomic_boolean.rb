# frozen_string_literal: true

require "test_helper"

class TestAtomicBoolean < Minitest::Test
  def test_init
    boolean = AtomicBoolean.new(false)
    assert_equal false, boolean.value
    assert_predicate boolean, :false?
  end

  if AtomicRuby::RACTOR_SAFE
    def test_shareable
      boolean = AtomicBoolean.new(true)
      assert Ractor.shareable?(boolean)
    end
  end

  def test_make_true
    boolean = AtomicBoolean.new(false)
    boolean.make_true
    assert_equal true, boolean.value
    assert_predicate boolean, :true?
  end

  if AtomicRuby::RACTOR_SAFE
    def test_make_true_in_ractor
      boolean = AtomicBoolean.new(false)
      ractors = 10.times.map do
        Ractor.new(boolean) do |shared_boolean|
          shared_boolean.make_true
        end
      end
      ractors.each(&:value)
      assert_equal true, boolean.value
      assert_predicate boolean, :true?
    end
  end

  def test_make_false
    boolean = AtomicBoolean.new(true)
    boolean.make_false
    assert_equal false, boolean.value
    assert_predicate boolean, :false?
  end

  if AtomicRuby::RACTOR_SAFE
    def test_make_false_in_ractor
      boolean = AtomicBoolean.new(true)
      ractors = 10.times.map do
        Ractor.new(boolean) do |shared_boolean|
          shared_boolean.make_false
        end
      end
      ractors.each(&:value)
      assert_equal false, boolean.value
      assert_predicate boolean, :false?
    end
  end

  def test_toggle
    boolean = AtomicBoolean.new(true)
    boolean.toggle
    assert_equal false, boolean.value
    assert_predicate boolean, :false?
  end

  if AtomicRuby::RACTOR_SAFE
    def test_toggle_in_ractor
      boolean = AtomicBoolean.new(true)
      ractors = 10.times.map do
        Ractor.new(boolean) do |shared_boolean|
          shared_boolean.toggle
        end
      end
      ractors.each(&:value)
      assert_equal true, boolean.value
      assert_predicate boolean, :true?
    end
  end
end
