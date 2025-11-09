# frozen_string_literal: true

require "test_helper"

class TestAtomicThreadPool < Minitest::Test
  def test_init
    pool = AtomicThreadPool.new(size: 2)
    assert_equal 2, pool.length
    assert_equal pool.length, pool.size
    assert_equal 0, pool.queue_length
    assert_equal pool.queue_length, pool.queue_size
    assert_equal 0, pool.active_count
    pool.shutdown
  end

  def test_init_with_invalid_size
    assert_raises ArgumentError do
      AtomicThreadPool.new(size: 0)
    end

    assert_raises ArgumentError do
      AtomicThreadPool.new(size: -1)
    end

    assert_raises ArgumentError do
      AtomicThreadPool.new(size: 2.5)
    end
  end

  def test_init_with_invalid_name
    assert_raises ArgumentError do
      AtomicThreadPool.new(size: 2, name: 123)
    end
  end

  if AtomicRuby::RACTOR_SAFE
    def test_not_ractor_shareable
      pool = AtomicThreadPool.new(size: 2)
      refute Ractor.shareable?(pool)
      pool.shutdown
    end
  end

  def test_start
    pool = AtomicThreadPool.new(size: 2, name: "Test Pool")
    assert_equal 2, Thread.list.count { |thread| thread.name =~ /AtomicThreadPool thread \d+ for Test Pool/ }
    pool.shutdown
  end

  def test_shutdown
    pool = AtomicThreadPool.new(size: 2, name: "Test Pool")
    pool.shutdown
    assert_equal 0, Thread.list.count { |thread| thread.name =~ /AtomicThreadPool thread \d+ for Test Pool/ }
  end

  def test_enqueue
    results = []
    pool = AtomicThreadPool.new(size: 2)
    5.times { |idx| pool << proc { results << idx + 1 } }
    pool.shutdown
    assert_equal [1, 2, 3, 4, 5], results.sort
  end

  def test_enqueue_after_shutdown
    pool = AtomicThreadPool.new(size: 2)
    pool.shutdown
    assert_raises AtomicThreadPool::EnqueuedWorkAfterShutdownError do
      pool << proc {}
    end
  end

  def test_enqueue_error_raising_work
    pool = AtomicThreadPool.new(size: 2)
    out, _err = capture_io do
      pool << proc { raise "oops" }
      sleep 0.1
    end
    assert_match(/AtomicThreadPool thread \d+ rescued:\nRuntimeError: oops/, out)
    pool.shutdown
  end

  def test_length
    pool = AtomicThreadPool.new(size: 2)
    assert_equal 2, pool.length
    assert_equal pool.length, pool.size
    pool.shutdown
    assert_equal 0, pool.length
    assert_equal pool.length, pool.size
  end

  def test_queue_length
    pool = AtomicThreadPool.new(size: 2)
    5.times { pool << proc { sleep 1 } }
    assert_operator pool.queue_length, :>=, 3
    assert_equal pool.queue_size, pool.queue_length
    pool.shutdown
    assert_equal 0, pool.queue_length
    assert_equal pool.queue_size, pool.queue_length
  end

  def test_active_count
    should_sleep = AtomicBoolean.new(true)
    pool = AtomicThreadPool.new(size: 2)
    pool << proc { sleep 0.1 while should_sleep.true?}
    sleep 0.1
    assert_equal 1, pool.active_count
    should_sleep.make_false
    pool.shutdown
  end
end
