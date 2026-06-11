# frozen_string_literal: true

require "benchmark/ips"
require_relative "../lib/atomic-ruby"

module Benchmark
  module IPS
    class Job
      class StreamReport
        def start_warming
          @out.puts "\n"
          @out.puts "ruby version:        #{RUBY_DESCRIPTION}"
          @out.puts "atomic-ruby version: #{AtomicRuby::VERSION}"
          @out.puts "\n"
          @out.puts "Warming up --------------------------------------"
        end
      end
    end
  end
end

Benchmark.ips do |x|
  x.report("Synchronized Condition Variable Wait/Signal") do
    flag = false
    mutex = Mutex.new
    condvar = ConditionVariable.new

    waiter = Thread.new do
      mutex.synchronize do
        condvar.wait(mutex) until flag
      end
    end

    mutex.synchronize do
      flag = true
      condvar.signal
    end
    waiter.join
  end

  x.report("Atomic Ruby Atomic Condition Variable Wait/Signal") do
    flag = AtomicBoolean.new(false)
    condvar = AtomicConditionVariable.new

    waiter = Thread.new { condvar.wait { flag.true? } }

    flag.make_true
    condvar.signal
    waiter.join
  end

  x.compare!
end
