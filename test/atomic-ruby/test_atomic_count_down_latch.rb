# frozen_string_literal: true

require "test_helper"

class TestAtomicCountDownLatch < Minitest::Test
  def test_init
    latch = AtomicCountDownLatch.new(5)
    assert_equal 5, latch.count
  end

  def test_shareable
    latch = AtomicCountDownLatch.new(5)
    assert Ractor.shareable?(latch)
  end

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

  def test_count_down_in_ractor
    latch = AtomicCountDownLatch.new(10)
    ractors = 10.times.map do
      Ractor.new(latch) do |shared_latch|
        shared_latch.count_down
      end
    end
    RUBY_VERSION >= "3.5" ? ractors.each(&:value) : ractors.each(&:take)
    assert_equal 0, latch.count
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

  def test_wait_in_ractor
    latch = AtomicCountDownLatch.new(5)
    countdown_ractors = 5.times.map do
      Ractor.new(latch) do |shared_latch|
        shared_latch.count_down
      end
    end
    wait_ractor = Ractor.new(latch) do |shared_latch|
      shared_latch.wait
      shared_latch.count
    end
    result = if RUBY_VERSION >= "3.5"
      countdown_ractors.each(&:value)
      wait_ractor.value
    else
      countdown_ractors.each(&:take)
      wait_ractor.take
    end
    assert_equal 0, result
  end
end
