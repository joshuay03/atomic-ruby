# frozen_string_literal: true

require_relative "atom"

module AtomicRuby
  class AtomicThreadPool
    class UnsupportedWorkTypeError < StandardError; end
    class InvalidWorkQueueingError < StandardError; end

    def initialize(size:)
      @size = size
      @queue = Atom.new([])
      @threads = []
      @started_threads = Atom.new(0)
      @stopping = Atom.new(false)

      start
    end

    def <<(work)
      unless work.is_a?(Proc) || work == :stop
        raise UnsupportedWorkTypeError, "expected work to be a `Proc`, got #{work.class}"
      end

      if @stopping.value
        raise InvalidWorkQueueingError, "cannot queue work during or after pool shutdown"
      end

      @queue.swap { |queue| queue << work }
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
          name = "AtomicRuby::AtomicThreadPool thread #{idx}"
          Thread.current.name = name

          @started_threads.swap { |count| count + 1 }

          loop do
            work = nil
            @queue.swap { |queue| work = queue.last; queue[0..-2] }
            case work
            when Proc
              begin
                work.call
              rescue => err
                puts "#{name} rescued:"
                puts "#{err.class}: #{err.message}"
                puts err.backtrace.join("\n")
              end
            when :stop
              @stopping.swap { true }
            when NilClass
              if @stopping.value
                break
              else
                Thread.pass
              end
            end
          end
        end
      end

      sleep(0.001) until @started_threads.value == @size
    end
  end
end
