# frozen_string_literal: true

require_relative "atom"
require_relative "linked_list"

module AtomicRuby
  class AtomicThreadPool
    class Error < StandardError; end

    class EnqueuedWorkAfterShutdownError < Error
      def message = "cannot queue work after shutdown"
    end

    def initialize(size:, name: nil)
      raise ArgumentError, "size must be a positive Integer" unless size.is_a?(Integer) && size > 0
      raise ArgumentError, "name must be a String" unless name.nil? || name.is_a?(String)

      @size = size
      @name = name

      @state = Atom.new(queue: LinkedList.new, shutdown: false)
      @started_threads = Atom.new(0)
      @threads = []

      start
    end

    def <<(work)
      state = @state.swap do |current_state|
        if current_state[:shutdown]
          current_state
        else
          current_state.merge(queue: current_state[:queue].prepend(work))
        end
      end
      raise EnqueuedWorkAfterShutdownError if state[:shutdown]
    end

    def length
      @threads.select(&:alive?).length
    end

    def queue_length
      @state.value[:queue].length
    end

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

    def start
      @size.times do |num|
        @threads << Thread.new(num) do |idx|
          thread_name = String.new("AtomicThreadPool thread #{idx}")
          thread_name << " for #{@name}" if @name
          Thread.current.name = thread_name

          @started_threads.swap { |current_count| current_count + 1 }

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
                current_state.merge(queue: current_state[:queue].rest)
              end
            end

            if should_shutdown
              break
            elsif work
              begin
                work.call
              rescue => err
                puts "#{thread_name} rescued:"
                puts "#{err.class}: #{err.message}"
                puts err.backtrace.join("\n")
              end
            else
              Thread.pass
            end
          end
        end
      end
      @threads.freeze

      Thread.pass until @started_threads.value == @size
    end
  end
end

AtomicThreadPool = AtomicRuby::AtomicThreadPool
