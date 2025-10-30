# frozen_string_literal: true

require "atomic_ruby/atomic_ruby"

module AtomicRuby
  class Atom
    def initialize(value)
      _initialize(Ractor.make_shareable(value))

      freeze
    end

    def value
      _value
    end

    def swap(&block)
      _swap { |old_value| Ractor.make_shareable(yield(old_value)) }
    end
  end
end

Atom = AtomicRuby::Atom
