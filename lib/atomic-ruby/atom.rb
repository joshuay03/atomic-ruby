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
      _swap do |old_value|
        Ractor.make_shareable(block.call(old_value))
      end
    end
  end
end

Atom = AtomicRuby::Atom
