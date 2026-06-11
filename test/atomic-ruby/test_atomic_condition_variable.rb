# frozen_string_literal: true

require "test_helper"

class TestAtomicConditionVariable < Minitest::Test
  def test_init
    condvar = AtomicConditionVariable.new
    assert_equal 0, condvar.waiter_count
  end

  def test_signal_wakes_one_waiter
    condvar = AtomicConditionVariable.new
    flag = AtomicBoolean.new(false)
    waiters = 4.times.map { Thread.new { condvar.wait { flag.true? } } }
    Thread.pass until condvar.waiter_count == 4

    flag.make_true
    assert condvar.signal

    Thread.pass while waiters.count(&:alive?) > 3
    assert_equal 3, condvar.waiter_count

    condvar.broadcast
    waiters.each(&:join)
    assert_equal 0, condvar.waiter_count
  end

  def test_signal_with_no_waiters
    condvar = AtomicConditionVariable.new
    refute condvar.signal
  end

  def test_broadcast_wakes_all_waiters
    condvar = AtomicConditionVariable.new
    flag = AtomicBoolean.new(false)
    waiters = 8.times.map { Thread.new { condvar.wait { flag.true? } } }
    Thread.pass until condvar.waiter_count == 8

    flag.make_true
    assert_equal 8, condvar.broadcast
    waiters.each(&:join)
    assert_equal 0, condvar.waiter_count
  end

  def test_broadcast_with_no_waiters
    condvar = AtomicConditionVariable.new
    assert_equal 0, condvar.broadcast
  end

  def test_wait_blocks_until_signalled
    condvar = AtomicConditionVariable.new
    flag = AtomicBoolean.new(false)

    waiter = Thread.new { condvar.wait { flag.true? } }
    Thread.pass until condvar.waiter_count == 1

    flag.make_true
    condvar.signal

    assert_equal true, waiter.value
    assert_equal 0, condvar.waiter_count
  end

  def test_wait_returns_immediately_when_predicate_truthy
    condvar = AtomicConditionVariable.new
    assert_equal :ok, condvar.wait { :ok }
    assert_equal 0, condvar.waiter_count
  end

  def test_no_lost_wakeup_under_contention
    100.times do
      condvar = AtomicConditionVariable.new
      flag = AtomicBoolean.new(false)

      consumer = Thread.new { condvar.wait { flag.true? } }
      producer = Thread.new do
        flag.make_true
        condvar.signal
      end

      assert consumer.join(5)
      producer.join
    end
  end
end
