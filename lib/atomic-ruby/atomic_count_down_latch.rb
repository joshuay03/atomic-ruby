# frozen_string_literal: true

require_relative "atom"

module AtomicRuby
  class AtomicCountDownLatch
    class InvalidCountError < StandardError; end
    class AlreadyCountedDownError < StandardError; end

    def initialize(count)
      unless count.is_a?(Integer)
        raise InvalidCountError, "expected count to be an `Integer`, got #{count.class}"
      end

      @count = Atom.new(count)

      Ractor.make_shareable(self)
    end

    def count
      @count.value
    end

    def count_down
      unless @count.value > 0
        raise AlreadyCountedDownError, "count has already reached zero"
      end

      @count.swap { |current_value| current_value - 1 }
    end

    def wait
      Thread.pass while @count.value > 0
    end
  end
end

AtomicCountDownLatch = AtomicRuby::AtomicCountDownLatch
