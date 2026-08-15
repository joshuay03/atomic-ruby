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
  x.report("Synchronized Queue Push/Pop") do
    queue = Thread::Queue.new
    20.times.map do
      Thread.new do
        100.times do |i|
          queue.push(i)
          queue.pop(true) rescue nil
        end
      end
    end.each(&:join)
  end

  x.report("Atomic Ruby Atomic Queue Push/Pop") do
    queue = AtomicQueue.new
    20.times.map do
      Thread.new do
        100.times do |i|
          queue.push(i)
          queue.pop
        end
      end
    end.each(&:join)
  end

  x.compare!
end
