# frozen_string_literal: true

require "benchmark"
require "concurrent-ruby"
require_relative "../lib/atomic-ruby"

class AtomicRubyAtomicBankAccount
  def initialize(balance)
    @balance = AtomicRuby::Atom.new(balance)
  end

  def balance
    @balance.value
  end

  def deposit(amount)
    @balance.swap { |current| current + amount }
    sleep(rand(0.1..0.2))
    @balance.value
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
    @balance.swap { |current| current + amount }
    sleep(rand(0.1..0.2))
    @balance.value
  end
end

class SynchronizedBankAccount
  attr_reader :balance

  def initialize(balance)
    @balance = balance
    @mutex = Mutex.new
  end

  def deposit(amount)
    @mutex.synchronize do
      @balance += amount
    end
    sleep(rand(0.1..0.2))
    @balance
  end
end

balances = []

r1 = Benchmark.measure do
  account = SynchronizedBankAccount.new(100)
  10_000.times.map { |i|
    Thread.new { account.deposit(i) }
  }.each(&:join)
  balances << account.balance
end

r2 = Benchmark.measure do
  account = ConcurrentRubyAtomicBankAccount.new(100)
  10_000.times.map { |i|
    Thread.new { account.deposit(i) }
  }.each(&:join)
  balances << account.balance
end

r3 = Benchmark.measure do
  account = AtomicRubyAtomicBankAccount.new(100)
  10_000.times.map { |i|
    Thread.new { account.deposit(i) }
  }.each(&:join)
  balances << account.balance
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
puts "Synchronized Bank Account:           #{r1.real.round(6)} seconds"
puts "Concurrent Ruby Atomic Bank Account: #{r2.real.round(6)} seconds"
puts "Atomic Ruby Atomic Bank Account:     #{r3.real.round(6)} seconds"
