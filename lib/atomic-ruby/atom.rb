# frozen_string_literal: true

module AtomicRuby
  class Atom
    def initialize(value)
      _initialize(value)
    end

    def value
      _value
    end

    def swap(&block)
      _swap(&block)
    end
  end
end
