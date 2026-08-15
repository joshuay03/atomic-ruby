# rbs_inline: enabled
# frozen_string_literal: true

require "atomic_ruby/atomic_ruby"

module AtomicRuby
  # Provides a lock-free FIFO queue using atomic operations.
  #
  # AtomicQueue is a multi-producer, multi-consumer queue backed by a
  # singly-linked list of nodes with atomic head and tail pointers.
  # Enqueueing and dequeueing use compare-and-swap operations so
  # concurrent producers and consumers never block one another.
  #
  # The queue is implemented as a Michael-Scott lock-free FIFO with a
  # dummy sentinel node. Both {#push} and {#pop} are O(1). Nodes are
  # Ruby-managed values, so the garbage collector reclaims dequeued
  # nodes once no thread holds a reference to them.
  #
  # @example Basic usage
  #   queue = AtomicQueue.new
  #   queue.push(1)
  #   queue.push(2)
  #   puts queue.pop #=> 1
  #   puts queue.pop #=> 2
  #   puts queue.pop #=> nil
  #
  # @example Producer/consumer coordination
  #   queue = AtomicQueue.new
  #   producers = 4.times.map do
  #     Thread.new { 100.times { |index| queue.push(index) } }
  #   end
  #   producers.each(&:join)
  #   puts queue.size #=> 400
  #
  # @note This class is NOT Ractor-safe as it stores mutable references
  #   to queued values that cannot be safely shared across ractors.
  class AtomicQueue
    # Creates a new empty queue.
    #
    # @example
    #   queue = AtomicQueue.new
    #
    # @rbs () -> void
    def initialize
      _initialize
    end

    # Enqueues a value at the tail of the queue.
    #
    # This operation is atomic and thread-safe. Multiple threads may
    # push concurrently without blocking one another.
    #
    # @param value [untyped] The value to enqueue
    # @return [self]
    #
    # @example
    #   queue = AtomicQueue.new
    #   queue.push(1)
    #   queue.push("two")
    #   queue.push(nil)
    #   puts queue.size #=> 3
    #
    # @rbs (untyped value) -> self
    def push(value)
      _push(value)
    end
    # Alias for {#push}.
    #
    # @rbs (untyped value) -> self
    alias << push

    # Dequeues the value at the head of the queue, or returns nil when
    # the queue is empty.
    #
    # This operation is atomic and thread-safe. Multiple threads may
    # pop concurrently without blocking one another.
    #
    # @return [untyped, nil] The dequeued value, or nil when the queue is empty
    #
    # @example
    #   queue = AtomicQueue.new
    #   queue.push(1)
    #   queue.push(2)
    #   puts queue.pop #=> 1
    #   puts queue.pop #=> 2
    #   puts queue.pop #=> nil
    #
    # @rbs () -> untyped
    def pop
      _pop
    end

    # Returns the number of values currently queued.
    #
    # This operation is atomic and thread-safe. The returned value
    # reflects the state at the time of the call, but may change
    # immediately after in concurrent environments.
    #
    # @return [Integer] The number of queued values
    #
    # @example
    #   queue = AtomicQueue.new
    #   queue.push(1)
    #   queue.push(2)
    #   puts queue.size #=> 2
    #
    # @rbs () -> Integer
    def size
      _size
    end
    # Alias for {#size}.
    #
    # @rbs () -> Integer
    alias length size

    # Returns true when the queue is empty.
    #
    # This operation is atomic and thread-safe. The returned value
    # reflects the state at the time of the call, but may change
    # immediately after in concurrent environments.
    #
    # @return [true, false] true when the queue has no values
    #
    # @example
    #   queue = AtomicQueue.new
    #   puts queue.empty? #=> true
    #   queue.push(1)
    #   puts queue.empty? #=> false
    #
    # @rbs () -> bool
    def empty?
      _empty_p
    end
  end
end

AtomicQueue = AtomicRuby::AtomicQueue
