# rbs_inline: enabled
# frozen_string_literal: true

require_relative "atom"

module AtomicRuby
  # Provides a fixed-size thread pool using atomic operations for work queuing.
  #
  # AtomicThreadPool maintains a fixed number of worker threads that process
  # work items from an atomic queue. The pool uses compare-and-swap operations
  # for thread-safe work enqueueing and state management.
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
    class Error < StandardError; end

    # Error raised when attempting to enqueue work after shutdown.
    class EnqueuedWorkAfterShutdownError < Error
      # @rbs () -> String
      def message = "cannot queue work after shutdown"
    end

    # Creates a new thread pool with the specified size.
    #
    # @param size [Integer] The number of worker threads to create (must be positive)
    # @param name [String, nil] Optional name for the thread pool (used in thread names)
    #
    # @raise [ArgumentError] if size is not a positive integer
    # @raise [ArgumentError] if name is provided but not a string
    #
    # @example Create a basic pool
    #   pool = AtomicThreadPool.new(size: 4)
    #
    # @example Create a named pool
    #   pool = AtomicThreadPool.new(size: 2, name: "Database Workers")
    #
    # @rbs (size: Integer, ?name: String?) -> void
    def initialize(size:, name: nil)
      raise ArgumentError, "size must be a positive Integer" unless size.is_a?(Integer) && size > 0
      raise ArgumentError, "name must be a String" unless name.nil? || name.is_a?(String)

      @size = size
      @name = name

      @state = Atom.new(queue: [], shutdown: false)
      @started_thread_count = Atom.new(0)
      @active_thread_count = Atom.new(0)
      @threads = []

      start
    end

    # Enqueues work to be executed by the thread pool.
    #
    # The work item must respond to #call (typically a Proc or lambda).
    # Work items are executed in FIFO order by available worker threads.
    # If all workers are busy, the work is queued atomically.
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
      state = @state.swap do |current_state|
        if current_state[:shutdown]
          current_state
        else
          current_state.merge(queue: [*current_state[:queue], work])
        end
      end
      raise EnqueuedWorkAfterShutdownError if state[:shutdown]
    end

    # Returns the number of currently alive worker threads.
    #
    # This count decreases as the pool shuts down and threads terminate.
    # During normal operation, this should equal the size parameter
    # passed to the constructor.
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
      @threads.select(&:alive?).length
    end
    # Alias for {#length}.
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
      @state.value[:queue].length
    end
    # Alias for {#queue_length}.
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
      already_shutdown = false
      @state.swap do |current_state|
        if current_state[:shutdown]
          already_shutdown = true
          current_state
        else
          current_state.merge(shutdown: true)
        end
      end
      return if already_shutdown

      Thread.pass until @state.value[:queue].empty?

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
    # @rbs () -> void
    def start
      @size.times do |num|
        @threads << Thread.new(num) do |idx|
          thread_name = String.new("AtomicThreadPool thread #{idx}")
          thread_name << " for #{@name}" if @name
          Thread.current.name = thread_name

          @started_thread_count.swap { |current_count| current_count + 1 }

          loop do
            work = nil
            should_shutdown = false

            @state.swap do |current_state|
              if current_state[:shutdown] && current_state[:queue].empty?
                should_shutdown = true
                current_state
              elsif current_state[:queue].empty?
                current_state
              else
                work = current_state[:queue].first
                current_state.merge(queue: current_state[:queue].drop(1))
              end
            end

            if should_shutdown
              break
            elsif work
              @active_thread_count.swap { |current_count| current_count + 1 }
              begin
                work.call
              rescue => err
                puts "#{thread_name} rescued:"
                puts "#{err.class}: #{err.message}"
                puts err.backtrace.join("\n")
              ensure
                @active_thread_count.swap { |current_count| current_count - 1 }
              end
            else
              Thread.pass
            end
          end
        end
      end
      @threads.freeze

      Thread.pass until @started_thread_count.value == @size
    end
  end
end

AtomicThreadPool = AtomicRuby::AtomicThreadPool
