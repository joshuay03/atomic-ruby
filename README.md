# AtomicRuby

![Version](https://img.shields.io/gem/v/atomic-ruby)
![Build](https://img.shields.io/github/actions/workflow/status/joshuay03/atomic-ruby/.github/workflows/main.yml?branch=main)

Atomic primitives for Ruby.

## Installation

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add atomic-ruby
```

If bundler is not being used to manage dependencies, install the gem by executing:

```bash
gem install atomic-ruby
```

## Usage

`AtomicRuby::Atom`:

```ruby
require "atomic-ruby"

atom = AtomicRuby::Atom.new(0)
p atom.value #=> 0
atom.swap { |current_value| current_value + 1 }
p atom.value #=> 1
atom.swap { |current_value| current_value + 1 }
p atom.value #=> 2
```

`AtomicRuby::AtomicBoolean`:

```ruby
require "atomic-ruby"

atom = AtomicRuby::AtomicBoolean.new(false)
p atom.value  #=> false
p atom.false? #=> true
p atom.true?  #=> false
atom.make_true
p atom.true?  #=> true
atom.toggle
p atom.false? #=> true
```

`AtomicRuby::AtomicThreadPool`:

```ruby
require "atomic-ruby"

results = []

pool = AtomicRuby::AtomicThreadPool.new(size: 4)
p pool.length       #=> 4

10.times do |idx|
  work = proc do
    sleep(0.5)
    results << (idx + 1)
  end
  pool << work
end
p pool.queue_length #=> 10
sleep(0.5)
p pool.queue_length #=> 2 (YMMV)

pool.shutdown
p pool.length       #=> 0
p pool.queue_length #=> 0

p results           #=> [8, 7, 10, 9, 6, 5, 3, 4, 2, 1]
p results.sort      #=> [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
```

`AtomicRuby::AtomicCountDownLatch`:

```ruby
require "atomic-ruby"

latch = AtomicRuby::AtomicCountDownLatch.new(3)
p latch.count #=> 3

threads = 3.times.map do
  Thread.new do
    sleep(rand(5))
    latch.count_down
  end
end

latch.wait
p latch.count #=> 0
```

## Benchmarks

<details>

<summary>AtomicRuby::Atom</summary>

<br>

```ruby
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
        25.times do
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

puts "\n"
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
```

```
> bundle exec rake compile && bundle exec ruby examples/atom_benchmark.rb

ruby version:            ruby 3.4.4 (2025-05-14 revision a38531fd3f) +YJIT +PRISM [arm64-darwin24]
concurrent-ruby version: 1.3.5
atomic-ruby version:     0.4.0

Balances:
Synchronized Bank Account Balance:           975
Concurrent Ruby Atomic Bank Account Balance: 975
Atomic Ruby Atomic Bank Account Balance:     975

Benchmark Results:
Synchronized Bank Account:           5.110062 seconds
Concurrent Ruby Atomic Bank Account: 5.107966 seconds
Atomic Ruby Atomic Bank Account:     5.107739 seconds
```

</details>

<details>

<summary>AtomicRuby::AtomicBoolean</summary>

```ruby
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
```

```
> bundle exec rake compile && bundle exec ruby examples/atomic_boolean_benchmark.rb

ruby version:            ruby 3.4.4 (2025-05-14 revision a38531fd3f) +YJIT +PRISM [arm64-darwin24]
concurrent-ruby version: 1.3.5
atomic-ruby version:     0.4.0

Warming up --------------------------------------
Synchronized Boolean Toggle
                       102.000 i/100ms
Concurrent Ruby Atomic Boolean Toggle
                        88.000 i/100ms
Atomic Ruby Atomic Boolean Toggle
                       109.000 i/100ms
Calculating -------------------------------------
Synchronized Boolean Toggle
                          1.062k (± 2.5%) i/s  (941.81 μs/i) -      5.406k in   5.094827s
Concurrent Ruby Atomic Boolean Toggle
                        981.495 (± 3.5%) i/s    (1.02 ms/i) -      4.928k in   5.027167s
Atomic Ruby Atomic Boolean Toggle
                          1.274k (± 1.5%) i/s  (784.70 μs/i) -      6.431k in   5.047458s

Comparison:
Atomic Ruby Atomic Boolean Toggle:         1274.4 i/s
Synchronized Boolean Toggle:               1061.8 i/s - 1.20x  slower
Concurrent Ruby Atomic Boolean Toggle:      981.5 i/s - 1.30x  slower
```

</details>

<details>

<summary>AtomicRuby::AtomicThreadPool</summary>

<br>

```ruby
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
```

```
> bundle exec rake compile && bundle exec ruby examples/atomic_thread_pool_benchmark.rb

ruby version:            ruby 3.4.4 (2025-05-14 revision a38531fd3f) +YJIT +PRISM [arm64-darwin24]
concurrent-ruby version: 1.3.5
atomic-ruby version:     0.4.0

Benchmark Results:
Concurrent Ruby Thread Pool:    5.02207 seconds
Atomic Ruby Atomic Thread Pool: 4.503302 seconds
```

</details>

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `bundle exec rake` to run the tests.
You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the
version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version,
push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[joshuay03]/atomic-ruby. This project is
intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the
[code of conduct](https://github.com/[joshuay03]/atomic-ruby/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the AtomicRuby project's codebases, issue trackers, chat rooms and mailing lists is expected to
follow the [code of conduct](https://github.com/[joshuay03]/atomic-ruby/blob/main/CODE_OF_CONDUCT.md).
