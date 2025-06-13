# frozen_string_literal: true

require "benchmark/ips"
require "concurrent-ruby"
require_relative "../lib/atomic-ruby"

module Benchmark
  module IPS
    class Job
      class StreamReport
        def start_warming
          @out.puts "\n"
          @out.puts "ruby version:            #{RUBY_DESCRIPTION}"
          @out.puts "concurrent-ruby version: #{Concurrent::VERSION}"
          @out.puts "atomic-ruby version:     #{AtomicRuby::VERSION}"
          @out.puts "\n"
          @out.puts "Warming up --------------------------------------"
        end
      end
    end
  end
end

Benchmark.ips do |x|
  x.report("Synchronized Boolean Toggle") do
    boolean = false
    mutex = Mutex.new
    20.times.map do
      Thread.new do
        100.times do
          mutex.synchronize do
            boolean = !boolean
          end
        end
      end
    end.each(&:join)
  end

  x.report("Concurrent Ruby Atomic Boolean Toggle") do
    boolean = Concurrent::AtomicBoolean.new(false)
    20.times.map do
      Thread.new do
        100.times do
          # Not exactly atomic, but this
          # is the closest matching API.
          boolean.value = !boolean.value
        end
      end
    end.each(&:join)
  end

  x.report("Atomic Ruby Atomic Boolean Toggle") do
    boolean = AtomicRuby::AtomicBoolean.new(false)
    20.times.map do
      Thread.new do
        100.times do
          boolean.toggle
        end
      end
    end.each(&:join)
  end

  x.compare!
end
