# frozen_string_literal: true

module AtomicRuby
  class Atom
    def initialize(value)
      _initialize(value)

      Ractor.make_shareable(self)
    end

    def value
      _value
    end

    def swap(&block)
      _swap(&block)
    end
  end
end

Atom = AtomicRuby::Atom
