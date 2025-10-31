# frozen_string_literal: true

require "atomic_ruby/atomic_ruby"

module AtomicRuby
  class Atom
    def initialize(value)
      _initialize(make_shareable(value))

      freeze if RACTOR_SAFE
    end

    def value
      _value
    end

    def swap(&block)
      _swap do |old_value|
        make_shareable(block.call(old_value))
      end
    end

    private

    def make_shareable(value)
      if RACTOR_SAFE
        Ractor.make_shareable(value)
      else
        value
      end
    end
  end
end

Atom = AtomicRuby::Atom
