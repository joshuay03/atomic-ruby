# frozen_string_literal: true

require_relative "atomic-ruby/version"
require_relative "atomic-ruby/atomic_ruby"
require_relative "atomic-ruby/atom"
require_relative "atomic-ruby/atomic_thread_pool"

module AtomicRuby
  class Error < StandardError; end
end
