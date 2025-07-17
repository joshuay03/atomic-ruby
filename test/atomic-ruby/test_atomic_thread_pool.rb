# frozen_string_literal: true

require "test_helper"

class TestAtomicThreadPool < Minitest::Test
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

  def test_queue
    results = []
    pool = AtomicThreadPool.new(size: 2)
    5.times { |idx| pool << ->{ results << idx + 1 } }
    pool.shutdown
    assert_equal [1, 2, 3, 4, 5], results.sort
  end

  def test_queue_with_invalid_work
    pool = AtomicThreadPool.new(size: 2)
    assert_raises AtomicThreadPool::UnsupportedWorkTypeError do
      pool << 1
    end
    pool.shutdown
  end

  def test_queue_after_shutdown
    pool = AtomicThreadPool.new(size: 2)
    pool.shutdown
    assert_raises AtomicThreadPool::InvalidWorkQueueingError do
      pool << -> {}
    end
  end

  def test_queue_error_raising_work
    pool = AtomicThreadPool.new(size: 2)
    out, _err = capture_io do
      pool << -> { raise "oops" }
      sleep 1
    end
    assert_match(/AtomicThreadPool thread \d+ rescued:\nRuntimeError: oops/, out)
    pool.shutdown
  end

  def test_length
    pool = AtomicThreadPool.new(size: 2)
    assert_equal 2, pool.length
    pool.shutdown
    assert_equal 0, pool.length
  end

  def test_queue_length
    pool = AtomicThreadPool.new(size: 2)
    5.times { pool << -> { sleep 1 } }
    assert_equal 5, pool.queue_length
    pool.shutdown
    assert_equal 0, pool.queue_length
  end
end
