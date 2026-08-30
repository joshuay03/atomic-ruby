# rbs_inline: enabled
# frozen_string_literal: true

require "atomic_ruby/atomic_ruby"

module AtomicRuby
  # Provides lock-free wait/signal coordination using atomic operations.
  #
  # AtomicConditionVariable lets one or more threads park until another
  # thread signals them, without the paired `Mutex` that Ruby's
  # `ConditionVariable` requires.
  #
  # Waiters supply a predicate that is checked again after registration,
  # preventing signals sent after a relevant state change from being lost.
  #
  # @example Basic usage
  #   condvar = AtomicConditionVariable.new
  #   ready = AtomicBoolean.new(false)
  #
  #   waiter = Thread.new do
  #     condvar.wait { ready.true? }
  #     puts "ready"
  #   end
  #
  #   ready.make_true
  #   condvar.signal
  #
  # @example Worker loop draining an atomic queue
  #   condvar.wait do
  #     work = queue.pop
  #     work || shutdown.true?
  #   end
  #
  # @note This class is NOT Ractor-safe as it parks `Thread` references,
  #   which cannot be shared across ractors.
  class AtomicConditionVariable
    # Creates a new condition variable with no parked threads.
    #
    # @example
    #   condvar = AtomicConditionVariable.new
    #
    # @rbs () -> void
    def initialize
      _initialize
    end

    # Returns the number of currently parked waiters.
    #
    # This operation is atomic and thread-safe. The returned value reflects
    # the state at the time of the call, but may change immediately after
    # in concurrent environments.
    #
    # @return [Integer] The number of currently parked waiters
    #
    # @example
    #   condvar = AtomicConditionVariable.new
    #   puts condvar.waiter_count #=> 0
    #
    # @rbs () -> Integer
    def waiter_count
      _waiter_count
    end

    # Wakes one parked waiter, or no-ops if none are parked.
    #
    # @return [true, false] true if a waiter was signalled, false otherwise
    #
    # @example
    #   condvar = AtomicConditionVariable.new
    #   condvar.signal #=> false
    #
    # @rbs () -> bool
    def signal
      thread = _shift_thread
      return false unless thread

      thread.wakeup rescue nil
      true
    end

    # Wakes every parked waiter.
    #
    # @return [Integer] The number of waiters signalled
    #
    # @example
    #   condvar = AtomicConditionVariable.new
    #   condvar.broadcast #=> 0
    #
    # @rbs () -> Integer
    def broadcast
      threads = _drain_threads
      threads.each { |thread| thread.wakeup rescue nil }
      threads.size
    end

    # Blocks until the given block returns a truthy value, then returns that
    # value.
    #
    # The block may run more than once and may run concurrently with a
    # signalling thread. Rechecking it after registration prevents lost
    # wakeups. Interrupted waits are unregistered before the exception is
    # propagated.
    #
    # @yieldreturn [untyped] Truthy to wake, falsy to keep waiting
    # @return [untyped] The first truthy value returned by the block
    #
    # @example Simple wait
    #   condvar = AtomicConditionVariable.new
    #   ready = AtomicBoolean.new(false)
    #
    #   Thread.new do
    #     sleep(1)
    #     ready.make_true
    #     condvar.signal
    #   end
    #
    #   condvar.wait { ready.true? } #=> true
    #
    # @rbs () { () -> untyped } -> untyped
    def wait
      result = yield
      return result if result

      self_thread = Thread.current
      loop do
        Thread.handle_interrupt(Exception => :never) do
          waiter = _add_waiter(self_thread)
          begin
            Thread.handle_interrupt(Exception => :immediate) do
              result = yield
              return result if result

              Thread.stop
            end
          ensure
            _remove_waiter(waiter)
          end
        end
      end
    end
  end
end

AtomicConditionVariable = AtomicRuby::AtomicConditionVariable
