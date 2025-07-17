# frozen_string_literal: true

require "test_helper"

class TestAtomicCountDownLatch < Minitest::Test
  def test_with_invalid_count
    assert_raises AtomicCountDownLatch::InvalidCountError do
      AtomicCountDownLatch.new(0.5)
    end
  end

  def test_count
    latch = AtomicCountDownLatch.new(1)
    assert_equal 1, latch.count
  end

  def test_count_down
    latch = AtomicCountDownLatch.new(1)
    assert_equal 0, latch.count_down
    assert_equal 0, latch.count
  end

  def test_count_down_when_already_counted_down
    latch = AtomicCountDownLatch.new(1)
    latch.count_down
    assert_raises AtomicCountDownLatch::AlreadyCountedDownError do
      latch.count_down
    end
  end

  def test_wait
    latch = AtomicCountDownLatch.new(1)
    latch.count_down
    assert_equal 0, latch.count
    latch.wait
    assert_equal 0, latch.count
  end

  def test_wait_with_multiple_threads
    latch = AtomicCountDownLatch.new(5)
    pool = AtomicThreadPool.new(size: 2)
    5.times do
      pool << -> {
        sleep 0.1
        latch.count_down
      }
    end
    latch.wait
    assert_equal 0, latch.count
  end
end
