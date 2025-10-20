# frozen_string_literal: true

require_relative "atom"

module AtomicRuby
  class AtomicBoolean
    def initialize(boolean)
      unless boolean.is_a?(TrueClass) || boolean.is_a?(FalseClass)
        raise ArgumentError, "boolean must be a TrueClass or FalseClass, got #{boolean.class}"
      end

      @boolean = Atom.new(boolean)

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
