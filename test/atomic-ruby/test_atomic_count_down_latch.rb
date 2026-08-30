# frozen_string_literal: true

require "test_helper"

class TestAtomicCountDownLatch < Minitest::Test
  def test_init
    latch = AtomicCountDownLatch.new(5)
    assert_equal 5, latch.count
  end

  def test_init_with_invalid_count
    assert_raises ArgumentError do
      AtomicCountDownLatch.new(0)
    end

    assert_raises ArgumentError do
      AtomicCountDownLatch.new(-1)
    end

    assert_raises ArgumentError do
      AtomicCountDownLatch.new(0.5)
    end
  end

  if AtomicRuby::RACTOR_SAFE
    def test_shareable
      latch = AtomicCountDownLatch.new(5)
      assert Ractor.shareable?(latch)
    end
  end

  def test_count_down
    latch = AtomicCountDownLatch.new(3)
    assert_equal 2, latch.count_down
    assert_equal 2, latch.count
    assert_equal 1, latch.count_down
    assert_equal 1, latch.count
    assert_equal 0, latch.count_down
    assert_equal 0, latch.count
  end

  def test_count_down_raises_when_already_zero
    latch = AtomicCountDownLatch.new(1)
    latch.count_down
    assert_raises AtomicCountDownLatch::AlreadyCountedDownError do
      latch.count_down
    end
  end

  if AtomicRuby::RACTOR_SAFE
    def test_count_down_cross_ractor
      latch = AtomicCountDownLatch.new(10)
      10.times.map do
        Ractor.new(latch) do |latch|
          latch.count_down
        end
      end.each(&:value)
      assert_equal 0, latch.count
    end
  end

  def test_wait
    latch = AtomicCountDownLatch.new(5)
    pool = AtomicThreadPool.new(size: 2)
    5.times do
      pool << proc {
        sleep 0.1
        latch.count_down
      }
    end
    assert_nil latch.wait
    assert_equal 0, latch.count
  end

  def test_wait_wakes_all_waiters
    latch = AtomicCountDownLatch.new(1)
    started_count = Atom.new(0)
    waiters = 5.times.map do
      Thread.new do
        started_count.swap { |current_count| current_count + 1 }
        latch.wait
      end
    end
    Thread.pass until started_count.value == 5
    sleep 0.01

    assert waiters.all?(&:alive?)
    latch.count_down

    assert_equal [nil] * 5, waiters.map(&:value)
  end

  if AtomicRuby::RACTOR_SAFE
    def test_wait_cross_ractor
      latch = AtomicCountDownLatch.new(5)
      countdown_ractors = 5.times.map do
        Ractor.new(latch) do |latch|
          sleep 0.1
          latch.count_down
        end
      end
      wait_ractor = Ractor.new(latch) do |latch|
        latch.wait
      end
      countdown_ractors.each(&:value)
      assert_nil wait_ractor.value
      assert_equal 0, latch.count
    end
  end
end
