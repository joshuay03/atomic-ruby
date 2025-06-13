# frozen_string_literal: true

require "benchmark"
require "concurrent-ruby"
require_relative "../lib/atomic-ruby"

results = []

2.times do |idx|
  result = Benchmark.measure do
    pool = case idx
    when 0 then Concurrent::FixedThreadPool.new(20)
    when 1 then AtomicRuby::AtomicThreadPool.new(size: 20)
    end

    100.times do
      pool << -> { sleep(0.2) }
    end

    100.times do
      pool << -> { 1_000_000.times.map(&:itself).sum }
    end

    pool.shutdown
    # concurrent-ruby's #shutdown does not wait for threads to terminate
    pool.wait_for_termination if idx == 0
  end

  results << result
end

puts "\n"
puts "ruby version:            #{RUBY_DESCRIPTION}"
puts "concurrent-ruby version: #{Concurrent::VERSION}"
puts "atomic-ruby version:     #{AtomicRuby::VERSION}"
puts "\n"
puts "Benchmark Results:"
puts "Concurrent Ruby Thread Pool:    #{results[0].real.round(6)} seconds"
puts "Atomic Ruby Atomic Thread Pool: #{results[1].real.round(6)} seconds"
