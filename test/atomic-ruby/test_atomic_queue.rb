# frozen_string_literal: true

require "test_helper"

class TestAtomicQueue < Minitest::Test
  def test_init
    queue = AtomicQueue.new
    assert_equal 0, queue.size
    assert_equal queue.size, queue.length
    assert queue.empty?
    assert_nil queue.pop
  end

  if AtomicRuby::RACTOR_SAFE
    def test_not_ractor_shareable
      queue = AtomicQueue.new
      refute Ractor.shareable?(queue)
    end
  end

  def test_push
    queue = AtomicQueue.new
    assert_same queue, queue.push(1)
    assert_equal 1, queue.size
    refute queue.empty?
  end

  def test_shovel_alias
    queue = AtomicQueue.new
    assert_same queue, queue << 1
    assert_equal 1, queue.size
  end

  def test_pop_preserves_fifo_order
    queue = AtomicQueue.new
    5.times { |idx| queue.push(idx + 1) }
    assert_equal [1, 2, 3, 4, 5], 5.times.map { queue.pop }
    assert_nil queue.pop
  end

  def test_pop_returns_nil_when_empty
    queue = AtomicQueue.new
    assert_nil queue.pop
    queue.push(1)
    queue.pop
    assert_nil queue.pop
  end

  def test_pop_preserves_nil_values
    queue = AtomicQueue.new
    queue.push(nil)
    queue.push(1)
    assert_nil queue.pop
    assert_equal 1, queue.size
    assert_equal 1, queue.pop
    assert queue.empty?
  end

  def test_concurrent_producers
    queue = AtomicQueue.new
    threads = 4.times.map do
      Thread.new { 250.times { |idx| queue.push(idx) } }
    end
    threads.each(&:join)
    assert_equal 1000, queue.size
  end

  def test_concurrent_consumers
    queue = AtomicQueue.new
    1000.times { |idx| queue.push(idx) }
    consumed = Atom.new([].freeze)
    threads = 4.times.map do
      Thread.new do
        while (value = queue.pop)
          consumed.swap { |list| (list + [value]).freeze }
        end
      end
    end
    threads.each(&:join)
    assert_equal 0, queue.size
    assert queue.empty?
    assert_equal (0...1000).to_a, consumed.value.sort
  end

  def test_concurrent_producers_and_consumers
    queue = AtomicQueue.new
    consumed = Atom.new([].freeze)
    producers = 4.times.map do
      Thread.new { 250.times { |idx| queue.push(idx) } }
    end
    consumers = 4.times.map do
      Thread.new do
        loop do
          value = queue.pop
          if value
            consumed.swap { |list| (list + [value]).freeze }
          elsif producers.none?(&:alive?) && queue.empty?
            break
          end
        end
      end
    end
    producers.each(&:join)
    consumers.each(&:join)
    assert_equal 0, queue.size
    assert_equal 1000, consumed.value.size
  end
end
