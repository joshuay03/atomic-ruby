# frozen_string_literal: true

require_relative "atom"

module AtomicRuby
  class AtomicCountDownLatch
    class Error < StandardError; end
    class AlreadyCountedDownError < Error; end

    def initialize(count)
      unless count.is_a?(Integer) && count > 0
        raise ArgumentError, "count must be a positive Integer"
      end

      @count = Atom.new(count)

      Ractor.make_shareable(self)
    end

    def count
      @count.value
    end

    def count_down
      already_counted_down = false
      new_count = @count.swap do |current_count|
        if current_count == 0
          already_counted_down = true
          current_count
        else
          current_count - 1
        end
      end
      raise AlreadyCountedDownError, "already counted down to zero" if already_counted_down

      new_count
    end

    def wait
      Thread.pass while @count.value > 0
    end
  end
end

AtomicCountDownLatch = AtomicRuby::AtomicCountDownLatch
