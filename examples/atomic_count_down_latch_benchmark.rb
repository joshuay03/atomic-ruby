# frozen_string_literal: true

require "benchmark"
require "concurrent-ruby"
require_relative "../lib/atomic-ruby"

results = []

2.times do |idx|
  result = Benchmark.measure do
    latch = case idx
    when 0 then Concurrent::CountDownLatch.new(1)
    when 1 then AtomicCountDownLatch.new(1)
    end

    thread = Thread.new do
      sleep(2)
      latch.count_down
    end

    latch.wait
    thread.join
  end

  results << result
end

puts "\n"
puts "ruby version:            #{RUBY_DESCRIPTION}"
puts "concurrent-ruby version: #{Concurrent::VERSION}"
puts "atomic-ruby version:     #{AtomicRuby::VERSION}"
puts "\n"
puts "Benchmark Results:"
puts "Concurrent Ruby Count Down Latch:    #{results[0].total.round(6)} CPU seconds, #{results[0].real.round(6)} elapsed seconds"
puts "Atomic Ruby Atomic Count Down Latch: #{results[1].total.round(6)} CPU seconds, #{results[1].real.round(6)} elapsed seconds"
