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

  def test_init_with_invalid_max_size
    assert_raises ArgumentError do
      AtomicThreadPool.new(size: 2, max_size: 1)
    end

    assert_raises ArgumentError do
      AtomicThreadPool.new(size: 2, max_size: 2.5)
    end
  end

  def test_init_with_invalid_name
    assert_raises ArgumentError do
      AtomicThreadPool.new(size: 2, name: 123)
    end
  end

  def test_init_with_invalid_on_error
    assert_raises ArgumentError do
      AtomicThreadPool.new(size: 2, on_error: "not a proc")
    end
  end

  if AtomicRuby::RACTOR_SAFE
    def test_not_ractor_shareable
      pool = AtomicThreadPool.new(size: 2)
      refute Ractor.shareable?(pool)
      pool.shutdown
    end

    def test_scales_up_in_multiple_ractors
      ractors = 2.times.map do
        Ractor.new do
          release = AtomicBoolean.new(false)
          pool = AtomicThreadPool.new(size: 1, max_size: 2)
          2.times { pool << proc { sleep 0.5 until release.true? } }

          begin
            deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
            until pool.size == 2
              raise "timed out waiting for condition" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

              sleep 0.001
            end

            pool.size
          ensure
            release.make_true
            pool.shutdown
          end
        end
      end

      assert_equal [2, 2], ractors.map(&:value)
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

  def test_enqueue_succeeds_when_queueing_happens_before_shutdown
    pool = AtomicThreadPool.new(size: 1)
    queue = pool.instance_variable_get(:@queue)
    enqueue_started = AtomicBoolean.new(false)
    continue_enqueue = AtomicBoolean.new(false)
    work_completed = AtomicBoolean.new(false)
    queue.define_singleton_method(:push) do |work|
      result = super(work)
      enqueue_started.make_true
      sleep 0.001 until continue_enqueue.true?
      result
    end

    enqueue_thread = Thread.new { pool << proc { work_completed.make_true } }
    wait_until { enqueue_started.true? }
    pool.shutdown
    continue_enqueue.make_true

    assert_nil enqueue_thread.value
    assert_predicate work_completed, :true?
    assert_equal 0, pool.queue_length
  end

  def test_enqueue_raises_when_shutdown_happens_before_queueing
    pool = AtomicThreadPool.new(size: 1)
    queue = pool.instance_variable_get(:@queue)
    enqueue_started = AtomicBoolean.new(false)
    continue_enqueue = AtomicBoolean.new(false)
    queue.define_singleton_method(:push) do |work|
      enqueue_started.make_true
      sleep 0.001 until continue_enqueue.true?
      super(work)
    end

    enqueue_thread = Thread.new { pool << proc {} }
    enqueue_thread.report_on_exception = false
    wait_until { enqueue_started.true? }
    pool.shutdown
    continue_enqueue.make_true

    assert_raises AtomicThreadPool::EnqueuedWorkAfterShutdownError do
      enqueue_thread.value
    end
    assert_equal 0, pool.queue_length
  end

  def test_enqueue_error_raising_work
    pool = AtomicThreadPool.new(size: 2)
    _out, err = capture_io do
      pool << proc { raise "oops" }
      pool.shutdown
    end
    assert_match(/AtomicThreadPool thread \d+ rescued:\n.+oops \(RuntimeError\)/, err)
  end

  def test_enqueue_error_raising_work_with_on_error
    errors = []
    pool = AtomicThreadPool.new(size: 2, on_error: ->(err) { errors << err })
    pool << proc { raise RuntimeError, "oops" }
    pool.shutdown
    assert_equal 1, errors.length
    assert_kind_of RuntimeError, errors.first
    assert_equal "oops", errors.first.message
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
    should_sleep = AtomicBoolean.new(true)
    pool = AtomicThreadPool.new(size: 2)
    5.times { pool << proc { sleep 0.1 while should_sleep.true? } }
    sleep 0.1
    assert_equal 3, pool.queue_length
    assert_equal pool.queue_size, pool.queue_length
    should_sleep.make_false
    pool.shutdown
    assert_equal 0, pool.queue_length
    assert_equal pool.queue_size, pool.queue_length
  end

  def test_active_count
    should_sleep = AtomicBoolean.new(true)
    pool = AtomicThreadPool.new(size: 2)
    pool << proc { sleep 0.1 while should_sleep.true? }
    sleep 0.1
    assert_equal 1, pool.active_count
    should_sleep.make_false
    pool.shutdown
  end

  def test_scales_up_for_blocking_work
    release = AtomicBoolean.new(false)
    pool = AtomicThreadPool.new(size: 1, max_size: Float::INFINITY)
    3.times { pool << proc { sleep 0.5 until release.true? } }

    begin
      wait_until { pool.size == 3 && pool.active_count == 3 }
      assert_equal 3, pool.active_count
    ensure
      release.make_true
      pool.shutdown
    end
  end

  def test_scales_up_promptly_for_a_burst_of_blocking_work
    gc_stress = GC.stress
    GC.stress = false
    release = AtomicBoolean.new(false)
    pool = AtomicThreadPool.new(size: 1, max_size: 8)
    8.times { pool << proc { sleep 0.5 until release.true? } }

    begin
      wait_until(timeout: 1) { pool.size == 8 && pool.active_count == 8 }
      assert_equal 8, pool.active_count
    ensure
      release.make_true
      pool.shutdown
      GC.stress = gc_stress
    end
  end

  def test_scales_up_for_mostly_blocking_work
    pool = AtomicThreadPool.new(size: 1, max_size: 2)
    pool.instance_variable_set(:@active_thread_count, Atom.new(1))
    previous_snapshot = [0, 0, 0, 0, 0, 0, 0]
    snapshot = [0, 0, 0, 10_000_000, 40_000_000, 60_000_000, 10_000_000]

    assert pool.send(:should_grow?, previous_snapshot, snapshot, [0, 0, 0], 0.05)
  ensure
    pool&.shutdown
  end

  def test_does_not_scale_up_for_cpu_bound_work
    release = AtomicBoolean.new(false)
    pool = AtomicThreadPool.new(size: 1, max_size: 3)
    pool << proc { 1 while release.false? }
    pool << proc {}

    begin
      wait_until { pool.active_count == 1 && pool.queue_size == 1 }
      sleep 0.3
      assert_equal 1, pool.size
    ensure
      release.make_true
      pool.shutdown
    end
  end

  def test_does_not_scale_up_for_mostly_cpu_bound_work
    release = AtomicBoolean.new(false)
    pool = AtomicThreadPool.new(size: 2, max_size: 4)
    4.times do
      pool << proc do
        until release.true?
          10_000.times.sum { |index| index * 2 }
          sleep 0.0001
        end
      end
    end

    begin
      wait_until { pool.active_count == 2 && pool.queue_size == 2 }
      sleep 0.3
      assert_equal 2, pool.size
    ensure
      release.make_true
      pool.shutdown
    end
  end

  def test_scales_down_after_blocking_work
    release = AtomicBoolean.new(false)
    pool = AtomicThreadPool.new(size: 1, max_size: 3)
    3.times { pool << proc { sleep 0.5 until release.true? } }

    begin
      wait_until { pool.size == 3 }
      release.make_true
      wait_until(timeout: 15) { pool.size == 1 }
      assert_equal 1, pool.size
    ensure
      release.make_true
      pool.shutdown
    end
  end

  private

  def wait_until(timeout: 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until yield
      raise "timed out waiting for condition" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.001
    end
  end
end
