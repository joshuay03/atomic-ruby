# frozen_string_literal: true

require "atomic_ruby/atomic_ruby"

require_relative "atomic-ruby/version"
require_relative "atomic-ruby/atom"
require_relative "atomic-ruby/atomic_boolean"
require_relative "atomic-ruby/atomic_thread_pool"
require_relative "atomic-ruby/atomic_count_down_latch"

Atom = AtomicRuby::Atom
AtomicBoolean = AtomicRuby::AtomicBoolean
AtomicThreadPool = AtomicRuby::AtomicThreadPool
AtomicCountDownLatch = AtomicRuby::AtomicCountDownLatch
