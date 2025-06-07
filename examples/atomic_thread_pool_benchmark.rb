# frozen_string_literal: true

require "benchmark"
require "concurrent-ruby"
require_relative "../lib/atomic-ruby"

results = []

2.times do |idx|
  result = Benchmark.measure do
    pool = case idx
    when 0 then Concurrent::FixedThreadPool.new(5)
    when 1 then AtomicRuby::AtomicThreadPool.new(size: 5)
    end

    20.times do
      pool << -> { sleep(0.25) }
    end

    20.times do
      pool << -> { 100_000.times.map(&:itself).sum }
    end

    # concurrent-ruby does not wait for threads to die on shutdown
    threads = if idx == 0
      pool.instance_variable_get(:@pool).map { |worker| worker.instance_variable_get(:@thread) }
    end
    pool.shutdown
    threads&.each(&:join)
  end

  results << result
end

puts "ruby version:            #{RUBY_DESCRIPTION}"
puts "concurrent-ruby version: #{Concurrent::VERSION}"
puts "atomic-ruby version:     #{AtomicRuby::VERSION}"
puts "\n"
puts "Benchmark Results:"
puts "Concurrent Ruby Thread Pool:    #{results[0].real.round(6)} seconds"
puts "Atomic Ruby Atomic Thread Pool: #{results[1].real.round(6)} seconds"
