# frozen_string_literal: true

require "test_helper"

class TestAtomicBoolean < Minitest::Test
  def test_init
    boolean = AtomicBoolean.new(false)
    assert_equal false, boolean.value
    assert_predicate boolean, :false?
    refute_predicate boolean, :true?
  end

  def test_init_with_invalid_value
    assert_raises ArgumentError do
      AtomicBoolean.new(nil)
    end

    assert_raises ArgumentError do
      AtomicBoolean.new("true")
    end

    assert_raises ArgumentError do
      AtomicBoolean.new(1)
    end
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
    refute_predicate boolean, :false?
  end

  if AtomicRuby::RACTOR_SAFE
    def test_make_true_cross_ractor
      boolean = AtomicBoolean.new(false)
      10.times.map do
        Ractor.new(boolean) do |boolean|
          boolean.make_true
        end
      end.each(&:value)
      assert_equal true, boolean.value
    end
  end

  def test_make_false
    boolean = AtomicBoolean.new(true)
    boolean.make_false
    assert_equal false, boolean.value
    assert_predicate boolean, :false?
    refute_predicate boolean, :true?
  end

  if AtomicRuby::RACTOR_SAFE
    def test_make_false_cross_ractor
      boolean = AtomicBoolean.new(true)
      10.times.map do
        Ractor.new(boolean) do |boolean|
          boolean.make_false
        end
      end.each(&:value)
      assert_equal false, boolean.value
    end
  end

  def test_toggle
    boolean = AtomicBoolean.new(true)
    boolean.toggle
    assert_equal false, boolean.value
    boolean.toggle
    assert_equal true, boolean.value
  end

  if AtomicRuby::RACTOR_SAFE
    def test_toggle_cross_ractor
      boolean = AtomicBoolean.new(true)
      10.times.map do
        Ractor.new(boolean) do |boolean|
          boolean.toggle
        end
      end.each(&:value)
      assert_equal true, boolean.value
    end
  end
end
