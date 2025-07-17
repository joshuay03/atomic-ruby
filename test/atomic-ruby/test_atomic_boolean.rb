# frozen_string_literal: true

require "test_helper"

class TestAtomicBoolean < Minitest::Test
  def test_init
    boolean = AtomicBoolean.new(false)
    assert_equal false, boolean.value
    assert_predicate boolean, :false?
  end

  def test_make_true
    boolean = AtomicBoolean.new(false)
    boolean.make_true
    assert_equal true, boolean.value
    assert_predicate boolean, :true?
  end

  def test_make_false
    boolean = AtomicBoolean.new(true)
    boolean.make_false
    assert_equal false, boolean.value
    assert_predicate boolean, :false?
  end

  def test_toggle
    boolean = AtomicBoolean.new(true)
    boolean.toggle
    assert_equal false, boolean.value
    assert_predicate boolean, :false?
  end
end
