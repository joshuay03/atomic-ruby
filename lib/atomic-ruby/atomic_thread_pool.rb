# frozen_string_literal: true

require_relative "atom"
require_relative "atomic_boolean"

module AtomicRuby
  class AtomicThreadPool
    class UnsupportedWorkTypeError < StandardError; end
    class InvalidWorkQueueingError < StandardError; end

    def initialize(size:, name: nil)
      @size = size
      @name = name
      @queue = Atom.new([])
      @threads = []
      @started_threads = Atom.new(0)
      @stopping = AtomicBoolean.new(false)

      start
    end

    def <<(work)
      unless work.is_a?(Proc) || work == :stop
        raise UnsupportedWorkTypeError, "expected work to be a `Proc`, got #{work.class}"
      end

      if @stopping.true?
        raise InvalidWorkQueueingError, "cannot queue work during or after pool shutdown"
      end

      @queue.swap { |current_queue| current_queue += [work] }
      true
    end

    def length
      @threads.select(&:alive?).length
    end

    def queue_length
      @queue.value.length
    end

    def shutdown
      self << :stop
      @threads.each(&:join)
      true
    end

    private

    def start
      @threads = @size.times.map do |num|
        Thread.new(num) do |idx|
          thread_name = String.new("AtomicThreadPool thread #{idx}")
          thread_name << " for #{@name}" if @name
          Thread.current.name = thread_name

          @started_threads.swap { |current_count| current_count + 1 }

          loop do
            work = nil
            @queue.swap { |current_queue| work = current_queue.last; current_queue[0..-2] }
            case work
            when Proc
              begin
                work.call
              rescue => err
                puts "#{thread_name} rescued:"
                puts "#{err.class}: #{err.message}"
                puts err.backtrace.join("\n")
              end
            when :stop
              @stopping.make_true
            when NilClass
              if @stopping.true?
                break
              else
                Thread.pass
              end
            end
          end
        end
      end

      Thread.pass until @started_threads.value == @size
    end
  end
end

AtomicThreadPool = AtomicRuby::AtomicThreadPool
