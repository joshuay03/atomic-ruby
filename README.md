# AtomicRuby

![Version](https://img.shields.io/gem/v/atomic-ruby)
![Build](https://img.shields.io/github/actions/workflow/status/joshuay03/atomic-ruby/.github/workflows/main.yml?branch=main)

Atomic ([CAS](https://en.wikipedia.org/wiki/Compare-and-swap)) primitives for Ruby.

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

`Atom`:

```ruby
require "atomic-ruby"

atom = Atom.new(0)
p atom.value #=> 0
atom.swap { |current_value| current_value + 1 }
p atom.value #=> 1
atom.swap { |current_value| current_value + 1 }
p atom.value #=> 2
```

`AtomicBoolean`:

```ruby
require "atomic-ruby"

atom = AtomicBoolean.new(false)
p atom.value  #=> false
p atom.false? #=> true
p atom.true?  #=> false
atom.make_true
p atom.true?  #=> true
atom.toggle
p atom.false? #=> true
```

`AtomicThreadPool`:

```ruby
require "atomic-ruby"

results = []

pool = AtomicThreadPool.new(size: 4)
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

`AtomicCountDownLatch`:

```ruby
require "atomic-ruby"

latch = AtomicCountDownLatch.new(3)
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

> [!NOTE]
> `Atom`, `AtomicBoolean`, and `AtomicCountDownLatch` are Ractor-safe in Ruby 3.5+.

## Benchmarks

<details>

<summary>Atom</summary>

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
    @balance = Atom.new(balance)
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

ruby version:            ruby 3.5.0dev (2025-10-31T18:08:15Z master 980e18496e) +YJIT +PRISM [arm64-darwin25]
concurrent-ruby version: 1.3.5
atomic-ruby version:     0.8.0

Balances:
Synchronized Bank Account Balance:           975
Concurrent Ruby Atomic Bank Account Balance: 975
Atomic Ruby Atomic Bank Account Balance:     975

Benchmark Results:
Synchronized Bank Account:           5.105459 seconds
Concurrent Ruby Atomic Bank Account: 5.101044 seconds
Atomic Ruby Atomic Bank Account:     5.091892 seconds
```

</details>

<details>

<summary>AtomicBoolean</summary>

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
    boolean = AtomicBoolean.new(false)
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

ruby version:            ruby 3.5.0dev (2025-10-31T18:08:15Z master 980e18496e) +YJIT +PRISM [arm64-darwin25]
concurrent-ruby version: 1.3.5
atomic-ruby version:     0.8.0

Warming up --------------------------------------
Synchronized Boolean Toggle
                       154.000 i/100ms
Concurrent Ruby Atomic Boolean Toggle
                       127.000 i/100ms
Atomic Ruby Atomic Boolean Toggle
                       139.000 i/100ms
Calculating -------------------------------------
Synchronized Boolean Toggle
                          1.458k (± 7.3%) i/s  (685.85 μs/i) -      7.392k in   5.102733s
Concurrent Ruby Atomic Boolean Toggle
                          1.129k (± 9.7%) i/s  (886.10 μs/i) -      5.588k in   5.001783s
Atomic Ruby Atomic Boolean Toggle
                          1.476k (± 6.0%) i/s  (677.44 μs/i) -      7.367k in   5.017482s

Comparison:
Atomic Ruby Atomic Boolean Toggle:         1476.1 i/s
Synchronized Boolean Toggle:               1458.1 i/s - same-ish: difference falls within error
Concurrent Ruby Atomic Boolean Toggle:     1128.5 i/s - 1.31x  slower
```

</details>

<details>

<summary>AtomicThreadPool</summary>

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

ruby version:            ruby 3.5.0dev (2025-10-31T18:08:15Z master 980e18496e) +YJIT +PRISM [arm64-darwin25]
concurrent-ruby version: 1.3.5
atomic-ruby version:     0.8.1

Benchmark Results:
Concurrent Ruby Thread Pool:    5.139026 seconds
Atomic Ruby Atomic Thread Pool: 4.833597 seconds
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
