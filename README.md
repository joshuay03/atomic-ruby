# AtomicRuby

![Version](https://img.shields.io/gem/v/atomic-ruby)
![Build](https://badge.buildkite.com/42198db99cf0eb852d54a6f125d99e68a5c0cd2e1d63026913.svg)

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

`AtomicConditionVariable`:

```ruby
require "atomic-ruby"

condvar = AtomicConditionVariable.new
ready = AtomicBoolean.new(false)
p condvar.waiter_count #=> 0

waiter = Thread.new do
  condvar.wait { ready.true? }
end
Thread.pass until condvar.waiter_count == 1
p condvar.waiter_count #=> 1

ready.make_true
p condvar.signal       #=> true
waiter.join
p condvar.waiter_count #=> 0
```

`AtomicQueue`:

```ruby
require "atomic-ruby"

queue = AtomicQueue.new
p queue.empty? #=> true
p queue.size   #=> 0

queue.push(1)
queue << 2
queue << 3
p queue.size   #=> 3

p queue.pop    #=> 1
p queue.pop    #=> 2
p queue.pop    #=> 3
p queue.pop    #=> nil
p queue.empty? #=> true
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

Pass `max_size` to let the pool temporarily add workers when queued work is
held up by blocking operations. The pool measures time spent blocked outside
the GVL and waiting for it, so it does not add more threads when GVL contention
is the bottleneck. It returns to `size` when the queue drains.

```ruby
pool = AtomicThreadPool.new(size: 4, max_size: 16)

# Grow without a limit
pool = AtomicThreadPool.new(size: 4, max_size: Float::INFINITY)
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
> `Atom`, `AtomicBoolean`, and `AtomicCountDownLatch` are Ractor-safe in Ruby 4.0+. `AtomicConditionVariable` and
> `AtomicQueue` are not, since they hold mutable references (parked `Thread`s and queued values, respectively) which
> cannot be shared across ractors.

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
> bundle exec rake clobber && bundle exec rake compile && bundle exec ruby examples/atom_benchmark.rb

ruby version:            ruby 4.0.6 (2026-07-14 revision 03b6d3f889) +YJIT +PRISM [arm64-darwin23]
concurrent-ruby version: 1.3.6
atomic-ruby version:     0.15.0

Balances:
Synchronized Bank Account Balance:           975
Concurrent Ruby Atomic Bank Account Balance: 975
Atomic Ruby Atomic Bank Account Balance:     975

Benchmark Results:
Synchronized Bank Account:           5.117072 seconds
Concurrent Ruby Atomic Bank Account: 5.128366 seconds
Atomic Ruby Atomic Bank Account:     5.110595 seconds
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
> bundle exec rake clobber && bundle exec rake compile && bundle exec ruby examples/atomic_boolean_benchmark.rb

ruby version:            ruby 4.0.6 (2026-07-14 revision 03b6d3f889) +YJIT +PRISM [arm64-darwin23]
concurrent-ruby version: 1.3.6
atomic-ruby version:     0.15.0

Warming up --------------------------------------
          Synchronized Boolean Toggle   157.000 i/100ms
Concurrent Ruby Atomic Boolean Toggle   134.000 i/100ms
    Atomic Ruby Atomic Boolean Toggle   120.000 i/100ms
Calculating -------------------------------------
          Synchronized Boolean Toggle      1.629k (± 2.0%) i/s  (613.87 μs/i) -      8.164k in   5.011636s
Concurrent Ruby Atomic Boolean Toggle      1.325k (± 2.0%) i/s  (754.96 μs/i) -      6.700k in   5.058203s
    Atomic Ruby Atomic Boolean Toggle      1.190k (± 2.6%) i/s  (840.11 μs/i) -      6.000k in   5.040665s

Comparison:
          Synchronized Boolean Toggle:     1629.0 i/s
Concurrent Ruby Atomic Boolean Toggle:     1324.6 i/s - 1.23x  slower
    Atomic Ruby Atomic Boolean Toggle:     1190.3 i/s - 1.37x  slower
```

</details>

<details>

<summary>AtomicConditionVariable</summary>

```ruby
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
  x.report("Synchronized Condition Variable Wait/Signal") do
    flag = false
    mutex = Mutex.new
    condvar = ConditionVariable.new

    waiter = Thread.new do
      mutex.synchronize do
        condvar.wait(mutex) until flag
      end
    end

    mutex.synchronize do
      flag = true
      condvar.signal
    end
    waiter.join
  end

  x.report("Atomic Ruby Atomic Condition Variable Wait/Signal") do
    flag = AtomicBoolean.new(false)
    condvar = AtomicConditionVariable.new

    waiter = Thread.new { condvar.wait { flag.true? } }

    flag.make_true
    condvar.signal
    waiter.join
  end

  x.compare!
end
```

```
> bundle exec rake clobber && bundle exec rake compile && bundle exec ruby examples/atomic_condition_variable_benchmark.rb

ruby version:        ruby 4.0.6 (2026-07-14 revision 03b6d3f889) +YJIT +PRISM [arm64-darwin23]
atomic-ruby version: 0.15.0

Warming up --------------------------------------
      Synchronized Condition Variable Wait/Signal     3.977k i/100ms
Atomic Ruby Atomic Condition Variable Wait/Signal     3.885k i/100ms
Calculating -------------------------------------
      Synchronized Condition Variable Wait/Signal     39.458k (± 4.2%) i/s   (25.34 μs/i) -    198.850k in   5.039596s
Atomic Ruby Atomic Condition Variable Wait/Signal     39.046k (± 4.2%) i/s   (25.61 μs/i) -    198.135k in   5.074411s

Comparison:
      Synchronized Condition Variable Wait/Signal:    39457.5 i/s
Atomic Ruby Atomic Condition Variable Wait/Signal:    39045.9 i/s - same-ish: difference falls within error
```

</details>

<details>

<summary>AtomicQueue</summary>

```ruby
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
```

```
> bundle exec rake clobber && bundle exec rake compile && bundle exec ruby examples/atomic_queue_benchmark.rb

ruby version:        ruby 4.0.6 (2026-07-14 revision 03b6d3f889) +YJIT +PRISM [arm64-darwin23]
atomic-ruby version: 0.15.0

Warming up --------------------------------------
      Synchronized Queue Push/Pop   181.000 i/100ms
Atomic Ruby Atomic Queue Push/Pop   132.000 i/100ms
Calculating -------------------------------------
      Synchronized Queue Push/Pop      1.845k (± 2.1%) i/s  (541.91 μs/i) -      9.231k in   5.002394s
Atomic Ruby Atomic Queue Push/Pop      1.431k (± 6.8%) i/s  (698.64 μs/i) -      7.260k in   5.072143s

Comparison:
      Synchronized Queue Push/Pop:     1845.3 i/s
Atomic Ruby Atomic Queue Push/Pop:     1431.3 i/s - 1.29x  slower

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
> bundle exec rake clobber && bundle exec rake compile && bundle exec ruby examples/atomic_thread_pool_benchmark.rb

ruby version:            ruby 4.0.6 (2026-07-14 revision 03b6d3f889) +YJIT +PRISM [arm64-darwin23]
concurrent-ruby version: 1.3.8
atomic-ruby version:     0.15.0

Benchmark Results:
Concurrent Ruby Thread Pool:    5.030964 seconds
Atomic Ruby Atomic Thread Pool: 4.676908 seconds
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
