# frozen_string_literal: true

require "benchmark"
require "concurrent-ruby"
require_relative "../lib/atomic-ruby"

class SynchronizedBankAccount
  def initialize(balance)
    @balance = balance
    @mutex = Mutex.new
  end

  def balance
    @mutex.synchronize do
      @balance
    end
  end

  def deposit(amount)
    @mutex.synchronize do
      @balance += amount
    end
  end
end

class ConcurrentRubyAtomicBankAccount
  def initialize(balance)
    @balance = Concurrent::Atom.new(balance)
  end

  def balance
    @balance.value
  end

  def deposit(amount)
    @balance.swap { |current_balance| current_balance + amount }
  end
end

class AtomicRubyAtomicBankAccount
  def initialize(balance)
    @balance = AtomicRuby::Atom.new(balance)
  end

  def balance
    @balance.value
  end

  def deposit(amount)
    @balance.swap { |current_balance| current_balance + amount }
  end
end

balances = []
results = []

3.times do |idx|
  klass = case idx
  when 0 then SynchronizedBankAccount
  when 1 then ConcurrentRubyAtomicBankAccount
  when 2 then AtomicRubyAtomicBankAccount
  end

  result = Benchmark.measure do
    account = klass.new(100)

    5.times.map do |idx|
      Thread.new do
        100.times do
          account.deposit(idx + 1)
          sleep(0.2)
          account.deposit(idx + 2)
        end
      end
    end.each(&:join)

    balances << account.balance
  end

  results << result
end

puts "ruby version:            #{RUBY_DESCRIPTION}"
puts "concurrent-ruby version: #{Concurrent::VERSION}"
puts "atomic-ruby version:     #{AtomicRuby::VERSION}"
puts "\n"
puts "Balances:"
puts "Synchronized Bank Account Balance:           #{balances[0]}"
puts "Concurrent Ruby Atomic Bank Account Balance: #{balances[1]}"
puts "Atomic Ruby Atomic Bank Account Balance:     #{balances[2]}"
puts "\n"
puts "Benchmark Results:"
puts "Synchronized Bank Account:           #{results[0].real.round(6)} seconds"
puts "Concurrent Ruby Atomic Bank Account: #{results[1].real.round(6)} seconds"
puts "Atomic Ruby Atomic Bank Account:     #{results[2].real.round(6)} seconds"
