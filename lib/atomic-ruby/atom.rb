# frozen_string_literal: true

require "atomic_ruby/atomic_ruby"

module AtomicRuby
  class Atom
    def initialize(value)
      _initialize(value)
    end

    def value
      _value
    end

    def swap(&block)
      _swap do |old_value|
        make_shareable_if_needed(block.call(old_value))
      end
    end

    private

    def make_shareable_if_needed(value)
      if RACTOR_SAFE &&
         (_initialized_ractor.nil? || Ractor.current != _initialized_ractor)
        Ractor.make_shareable(value)
      else
        value
      end
    end
  end
end

Atom = AtomicRuby::Atom
