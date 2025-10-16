# frozen_string_literal: true

require_relative "atom"

module AtomicRuby
  class AtomicBoolean
    class InvalidBooleanError < StandardError; end

    def initialize(value)
      unless value.is_a?(TrueClass) || value.is_a?(FalseClass)
        raise InvalidBooleanError, "expected boolean to be a `TrueClass` or `FalseClass`, got #{value.class}"
      end

      @boolean = Atom.new(value)

      Ractor.make_shareable(self)
    end

    def value
      @boolean.value
    end

    def true?
      value == true
    end

    def false?
      value == false
    end

    def make_true
      @boolean.swap { true }
    end

    def make_false
      @boolean.swap { false }
    end

    def toggle
      @boolean.swap { |current_value| !current_value }
    end
  end
end

AtomicBoolean = AtomicRuby::AtomicBoolean
