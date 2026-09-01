# frozen_string_literal: true

require "benchmark"
require "concurrent-ruby"
require_relative "../lib/atomic-ruby"

fixed_results = []

2.times do |idx|
  result = Benchmark.measure do
    pool = case idx
    when 0 then Concurrent::FixedThreadPool.new(20)
    when 1 then AtomicThreadPool.new(size: 20)
    end

    100.times do
      pool << proc { sleep(0.2) }
    end

    100.times do
      pool << proc { 1_000_000.times.map(&:itself).sum }
    end

    pool.shutdown
    # concurrent-ruby's #shutdown does not wait for threads to terminate
    pool.wait_for_termination if idx == 0
  end

  fixed_results << result
end

adaptive_results = []

2.times do |idx|
  result = Benchmark.measure do
    pool = case idx
    when 0 then Concurrent.new_io_executor
    when 1 then AtomicThreadPool.new(size: 1, max_size: Float::INFINITY)
    end
    latch = case idx
    when 0 then Concurrent::CountDownLatch.new(100)
    when 1 then AtomicCountDownLatch.new(100)
    end

    100.times do
      pool << proc do
        sleep(0.2)
        latch.count_down
      end
    end

    latch.wait
    pool.shutdown
    # concurrent-ruby's #shutdown does not wait for threads to terminate
    pool.wait_for_termination if idx == 0
  end

  adaptive_results << result
end

puts "\n"
puts "ruby version:            #{RUBY_DESCRIPTION}"
puts "concurrent-ruby version: #{Concurrent::VERSION}"
puts "atomic-ruby version:     #{AtomicRuby::VERSION}"
puts "\n"
puts "Fixed Pool Results:"
puts "Concurrent Ruby Fixed Thread Pool: #{fixed_results[0].real.round(6)} seconds"
puts "Atomic Ruby Fixed Thread Pool:     #{fixed_results[1].real.round(6)} seconds"
puts "\n"
puts "Adaptive Pool Results:"
puts "Concurrent Ruby IO Thread Pool:   #{adaptive_results[0].real.round(6)} seconds"
puts "Atomic Ruby Adaptive Thread Pool: #{adaptive_results[1].real.round(6)} seconds"
