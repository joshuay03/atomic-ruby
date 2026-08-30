# rbs_inline: enabled
# frozen_string_literal: true

require_relative "atom"
require_relative "atomic_boolean"
require_relative "atomic_condition_variable"
require_relative "atomic_queue"

module AtomicRuby
  # Provides a thread pool using atomic operations for work queuing.
  #
  # AtomicThreadPool maintains a baseline number of worker threads that process
  # work items from an {AtomicQueue}. When `max_size` is provided, it can
  # temporarily add workers when work remains queued and its workers spend most
  # of their time blocked outside the GVL. Both enqueueing and dequeueing are
  # O(1) and lock-free, so concurrent producers and consumers never block one
  # another.
  #
  # @example Basic usage
  #   pool = AtomicThreadPool.new(size: 4)
  #   pool << proc { puts "Hello from worker thread!" }
  #   pool << proc { puts "Another work item" }
  #   pool.shutdown
  #
  # @example Processing work with results
  #   results = []
  #   pool = AtomicThreadPool.new(size: 2, name: "Calculator")
  #
  #   10.times do |index|
  #     pool << proc { results << index * 2 }
  #   end
  #
  #   pool.shutdown
  #   puts results.sort #=> [0, 2, 4, 6, 8, 10, 12, 14, 16, 18]
  #
  # @example Scaling for blocking work
  #   pool = AtomicThreadPool.new(size: 2, max_size: 8)
  #   20.times { pool << proc { Net::HTTP.get(uri) } }
  #   pool.shutdown
  #
  # @example Monitoring pool state
  #   pool = AtomicThreadPool.new(size: 3)
  #   puts pool.length        #=> 3
  #   puts pool.queue_length  #=> 0
  #   puts pool.active_count  #=> 0
  #
  #   5.times { pool << proc { sleep(1) } }
  #   puts pool.queue_length  #=> 2 (3 workers busy, 2 queued)
  #   puts pool.active_count  #=> 3 (3 workers processing)
  #
  # @note This class is NOT Ractor-safe as it contains mutable thread state
  #   that cannot be safely shared across ractors.
  class AtomicThreadPool
    AUTOSCALE_GROWTH_SAMPLES = 3
    AUTOSCALE_IDLE_TIME = 1
    AUTOSCALE_INTERVAL = 0.01
    AUTOSCALE_WINDOW = 0.05
    private_constant :AUTOSCALE_GROWTH_SAMPLES, :AUTOSCALE_IDLE_TIME, :AUTOSCALE_INTERVAL, :AUTOSCALE_WINDOW

    class Error < StandardError; end

    # Error raised when attempting to enqueue work after shutdown.
    class EnqueuedWorkAfterShutdownError < Error
      # @rbs () -> String
      def message = "cannot queue work after shutdown"
    end

    # Creates a new thread pool with the specified baseline size.
    #
    # When `max_size` is greater than `size`, the pool adds temporary workers
    # if work remains queued while its active workers spend most of their time
    # blocked outside the GVL, but not when Ruby execution is using the
    # available CPU.
    # Temporary workers leave after the queue remains empty, returning the pool
    # to its baseline size. Omitting `max_size` creates a fixed-size pool.
    #
    # @param size [Integer] The baseline number of worker threads (must be positive)
    # @param max_size [Integer, Float, nil] Maximum number of worker threads,
    #   `Float::INFINITY` for no limit, or nil for a fixed-size pool
    # @param name [String, nil] Optional name for the thread pool (used in thread names)
    # @param on_error [Proc, nil] Optional error handler called with the exception when
    #   a work item raises. Receives the exception as its argument. When nil, errors
    #   are printed to stderr
    #
    # @raise [ArgumentError] if size is not a positive integer
    # @raise [ArgumentError] if max_size is not an integer greater than or equal
    #   to size or `Float::INFINITY`
    # @raise [ArgumentError] if name is provided but not a string
    # @raise [ArgumentError] if on_error is provided but not a Proc
    #
    # @example Create a basic pool
    #   pool = AtomicThreadPool.new(size: 4)
    #
    # @example Create a named pool
    #   pool = AtomicThreadPool.new(size: 2, name: "Database Workers")
    #
    # @example Create an adaptive pool
    #   pool = AtomicThreadPool.new(size: 2, max_size: 8)
    #
    # @example Create a pool with a custom error handler
    #   errors = []
    #   pool = AtomicThreadPool.new(size: 2, on_error: ->(err) { errors << err })
    #
    # @rbs (size: Integer, ?max_size: (Integer | Float)?, ?name: String?, ?on_error: Proc?) -> void
    def initialize(size:, max_size: nil, name: nil, on_error: nil)
      raise ArgumentError, "size must be a positive Integer" unless size.is_a?(Integer) && size > 0
      valid_max_size = max_size.nil? || max_size == Float::INFINITY || (max_size.is_a?(Integer) && max_size >= size)
      raise ArgumentError, "max_size must be an Integer greater than or equal to size or Float::INFINITY" unless valid_max_size
      raise ArgumentError, "name must be a String" unless name.nil? || name.is_a?(String)
      raise ArgumentError, "on_error must be a Proc" unless on_error.nil? || on_error.is_a?(Proc)

      @size = size
      @max_size = max_size || size
      @name = name
      @on_error = on_error

      @queue = AtomicQueue.new
      @shutdown = AtomicBoolean.new(false)
      @work_available = AtomicConditionVariable.new
      @alive_thread_count = Atom.new(0)
      @active_thread_count = Atom.new(0)
      @threads = []
      @next_thread_number = 0
      if adaptive?
        @autoscale_available = AtomicConditionVariable.new
        @trim_requested = AtomicBoolean.new(false)
        @thread_pool_monitor = ThreadPoolMonitor.new
      end

      start
    end

    # Enqueues work to be executed by the thread pool.
    #
    # The work item must respond to #call (typically a Proc or lambda).
    # Work items are executed in FIFO order by available worker threads.
    # If all workers are busy, the work is queued atomically.
    # Enqueueing is O(1) regardless of current queue depth.
    #
    # @param work [#call] A callable object to be executed by a worker thread
    #
    # @raise [EnqueuedWorkAfterShutdownError] if the pool has been shut down
    #
    # @example Enqueue a simple task
    #   pool << proc { puts "Hello World" }
    #
    # @example Enqueue a lambda with parameters
    #   calculator = ->(a, b) { puts a + b }
    #   pool << proc { calculator.call(2, 3) }
    #
    # @example Enqueue work that captures variables
    #   name = "Alice"
    #   pool << proc { puts "Processing #{name}" }
    #
    # @rbs (Proc work) -> void
    def <<(work)
      raise EnqueuedWorkAfterShutdownError if @shutdown.true?

      @trim_requested&.make_false
      @queue.push(work)
      @work_available.signal
      @autoscale_available&.signal
    end

    # Returns the number of currently alive worker threads.
    #
    # This count decreases as the pool shuts down and threads terminate.
    # An adaptive pool may report a value between the `size` and `max_size`
    # parameters passed to the constructor.
    #
    # @return [Integer] The number of alive worker threads
    #
    # @example
    #   pool = AtomicThreadPool.new(size: 4)
    #   puts pool.length #=> 4
    #   pool.shutdown
    #   puts pool.length #=> 0
    #
    # @rbs () -> Integer
    def length
      @alive_thread_count.value
    end
    # Alias for {#length}.
    #
    # @rbs () -> Integer
    alias size length

    # Returns the number of work items currently queued for execution.
    #
    # This represents work that has been enqueued but not yet picked up
    # by a worker thread. A high queue length indicates that work is
    # being submitted faster than it can be processed.
    #
    # @return [Integer] The number of queued work items
    #
    # @example
    #   pool = AtomicThreadPool.new(size: 2)
    #   5.times { pool << proc { sleep(1) } }
    #   puts pool.queue_length #=> 3 (2 workers busy, 3 queued)
    #
    # @rbs () -> Integer
    def queue_length
      @queue.size
    end
    # Alias for {#queue_length}.
    #
    # @rbs () -> Integer
    alias queue_size queue_length

    # Returns the number of worker threads currently executing work.
    #
    # This represents threads that have picked up a work item and are
    # actively processing it. The count includes threads in the middle
    # of executing work.call, but excludes threads that are idle or
    # waiting for work.
    #
    # @return [Integer] The number of threads actively processing work
    #
    # @example Monitor active workers
    #   pool = AtomicThreadPool.new(size: 4)
    #   puts pool.active_count #=> 0
    #
    #   5.times { pool << proc { sleep(1) } }
    #   sleep(0.1) # Give threads time to pick up work
    #   puts pool.active_count #=> 4 (all workers busy)
    #   puts pool.queue_length #=> 1 (one item still queued)
    #
    # @example Calculate total load
    #   total_load = pool.active_count + pool.queue_length
    #   puts "Total pending work: #{total_load}"
    #
    # @rbs () -> Integer
    def active_count
      @active_thread_count.value
    end

    # Gracefully shuts down the thread pool.
    #
    # This method:
    # 1. Marks the pool as shutdown (preventing new work from being enqueued)
    # 2. Waits for all currently queued work to complete
    # 3. Waits for all worker threads to terminate
    #
    # After shutdown, all worker threads will be terminated and the pool
    # cannot be restarted. Attempting to enqueue work after shutdown
    # will raise an exception.
    #
    # @return [void]
    #
    # @raise [EnqueuedWorkAfterShutdownError] if work is enqueued after shutdown
    #
    # @example
    #   pool = AtomicThreadPool.new(size: 4)
    #   10.times { |index| pool << proc { puts index } }
    #   pool.shutdown # waits for all work to complete
    #   puts pool.length #=> 0
    #
    # @rbs () -> void
    def shutdown
      return if @shutdown.true?

      @shutdown.make_true
      @autoscale_available&.broadcast
      @work_available.broadcast
      @autoscaler&.join
      @threads.each(&:join)
    end

    private

    # Starts the worker threads for the thread pool.
    #
    # This method is called automatically during initialization.
    # It creates the specified number of worker threads and waits
    # for all threads to be fully started before returning.
    #
    # @return [void]
    #
    # @rbs () -> void
    def start
      @size.times { spawn_worker }

      if adaptive?
        @autoscaler = Thread.new do
          thread_name = String.new("AtomicThreadPool autoscaler")
          thread_name << " for #{@name}" if @name
          Thread.current.name = thread_name
          autoscale
        end
      end

      Thread.pass until @alive_thread_count.value == @size
    end

    # Returns whether the pool may grow beyond its baseline size.
    #
    # @return [true, false]
    #
    # @rbs () -> bool
    def adaptive?
      @max_size > @size
    end

    # Creates a worker thread.
    #
    # Temporary workers leave after the queue remains empty.
    #
    # @param temporary [true, false] whether the worker belongs above the baseline
    # @return [Thread]
    #
    # @rbs (?temporary: bool) -> Thread
    def spawn_worker(temporary: false)
      thread_number = @next_thread_number
      @next_thread_number += 1

      thread = Thread.new(thread_number) do |idx|
        thread_name = String.new("AtomicThreadPool thread #{idx}")
        thread_name << " for #{@name}" if @name
        Thread.current.name = thread_name

        @thread_pool_monitor&.register_worker
        @alive_thread_count.swap { |current_count| current_count + 1 }

        begin
          loop do
            work = nil
            should_exit = false

            @work_available.wait do
              work = @queue.pop
              unless work
                should_exit = @shutdown.true? && @queue.empty?
                should_exit ||= temporary && @trim_requested.true? && @queue.empty?
              end
              work || should_exit
            end

            break if should_exit

            @active_thread_count.swap { |current_count| current_count + 1 }
            begin
              @thread_pool_monitor&.start_work
              work.call
            rescue => err
              if @on_error
                @on_error.call(err)
              else
                warn "#{thread_name} rescued:"
                warn err.full_message
              end
            ensure
              @thread_pool_monitor&.stop_work
              @active_thread_count.swap { |current_count| current_count - 1 }
            end
          end
        ensure
          @alive_thread_count.swap { |current_count| current_count - 1 }
          @thread_pool_monitor&.unregister_worker
        end
      end

      @threads << thread
      thread
    end

    # Adds temporary workers while queued work is held up by blocked workers.
    #
    # @return [void]
    #
    # @rbs () -> void
    def autoscale
      previous_snapshot = @thread_pool_monitor.snapshot
      pressure_started_at = nil
      idle_started_at = nil
      growth_samples = 0
      phase_samples = [0, 0, 0]

      loop do
        @autoscale_available.wait do
          @shutdown.true? || !@queue.empty? || @alive_thread_count.value > @size
        end
        break if @shutdown.true?

        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        snapshot = @thread_pool_monitor.snapshot

        if @queue.empty?
          pressure_started_at = nil
          previous_snapshot = snapshot
          idle_started_at ||= now
          growth_samples = 0
          phase_samples.fill(0)

          if now - idle_started_at >= AUTOSCALE_IDLE_TIME
            @trim_requested.make_true
            @work_available.broadcast
          end
        else
          @trim_requested.make_false
          idle_started_at = nil

          if pressure_started_at.nil?
            previous_snapshot = snapshot
            pressure_started_at = now
            phase_samples.fill(0)
          elsif now - pressure_started_at >= AUTOSCALE_WINDOW
            if should_grow?(previous_snapshot, snapshot, phase_samples, now - pressure_started_at)
              growth_samples += 1
              if growth_samples >= AUTOSCALE_GROWTH_SAMPLES
                spawn_worker(temporary: true)
                growth_samples = 0
              end
            else
              growth_samples = 0
            end
            previous_snapshot = snapshot
            pressure_started_at = now
            phase_samples.fill(0)
          else
            3.times { |index| phase_samples[index] += snapshot[index] }
          end
        end

        sleep AUTOSCALE_INTERVAL
      end
    end

    # Returns whether another worker is likely to improve throughput.
    #
    # Requiring workers to spend a majority of their time blocked outside the
    # GVL recognizes blocking operations. The pool only grows while its workers
    # use less than half of one CPU, avoiding extra threads when Ruby
    # execution is the bottleneck without mistaking OS scheduling delays for
    # GVL contention.
    #
    # @param previous_snapshot [Array<Integer>] previous GVL state snapshot
    # @param snapshot [Array<Integer>] current GVL state snapshot
    # @param phase_samples [Array<Integer>] sampled current GVL states
    # @param elapsed_time [Float] seconds covered by the snapshots
    # @return [true, false]
    #
    # @rbs (Array[Integer] previous_snapshot, Array[Integer] snapshot, Array[Integer] phase_samples, Float elapsed_time) -> bool
    def should_grow?(previous_snapshot, snapshot, phase_samples, elapsed_time)
      @threads.select!(&:alive?)
      workers = @threads
      return false if workers.length >= @max_size
      return false if @active_thread_count.value < workers.length

      running_time = snapshot[3] - previous_snapshot[3]
      waiting_time = snapshot[4] - previous_snapshot[4]
      blocked_time = snapshot[5] - previous_snapshot[5]
      running_cpu_time = snapshot[6] - previous_snapshot[6]
      total_time = running_time + waiting_time + blocked_time

      minimum_measured_time = (AUTOSCALE_WINDOW * 1_000_000_000 * workers.length / 2).to_i
      if total_time < minimum_measured_time
        running_time, waiting_time, blocked_time = phase_samples
        total_time = running_time + waiting_time + blocked_time
      end

      total_time.positive? &&
        blocked_time * 2 > total_time &&
        running_cpu_time * 2 < elapsed_time * 1_000_000_000
    end
  end
end

AtomicThreadPool = AtomicRuby::AtomicThreadPool
