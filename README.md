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
the GVL and CPU time used while running Ruby, so it does not add more threads
when Ruby execution is the bottleneck. Temporary workers remain available
between blocking bursts, but retire when Ruby execution becomes the bottleneck
or they remain idle.

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
concurrent-ruby version: 1.3.8
atomic-ruby version:     0.15.5

Balances:
Synchronized Bank Account Balance:           975
Concurrent Ruby Atomic Bank Account Balance: 975
Atomic Ruby Atomic Bank Account Balance:     975

Benchmark Results:
Synchronized Bank Account:           5.104959 seconds
Concurrent Ruby Atomic Bank Account: 5.120305 seconds
Atomic Ruby Atomic Bank Account:     5.102732 seconds
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
concurrent-ruby version: 1.3.8
atomic-ruby version:     0.15.5

Warming up --------------------------------------
          Synchronized Boolean Toggle   165.000 i/100ms
Concurrent Ruby Atomic Boolean Toggle   132.000 i/100ms
    Atomic Ruby Atomic Boolean Toggle   119.000 i/100ms
Calculating -------------------------------------
          Synchronized Boolean Toggle      1.647k (± 2.1%) i/s  (606.98 μs/i) -      8.250k in   5.007598s
Concurrent Ruby Atomic Boolean Toggle      1.343k (± 1.9%) i/s  (744.55 μs/i) -      6.732k in   5.012307s
    Atomic Ruby Atomic Boolean Toggle      1.207k (± 1.9%) i/s  (828.31 μs/i) -      6.069k in   5.027033s

Comparison:
          Synchronized Boolean Toggle:     1647.5 i/s
Concurrent Ruby Atomic Boolean Toggle:     1343.1 i/s - 1.23x  slower
    Atomic Ruby Atomic Boolean Toggle:     1207.3 i/s - 1.36x  slower
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
atomic-ruby version: 0.15.5

Warming up --------------------------------------
      Synchronized Condition Variable Wait/Signal     4.062k i/100ms
Atomic Ruby Atomic Condition Variable Wait/Signal     4.133k i/100ms
Calculating -------------------------------------
      Synchronized Condition Variable Wait/Signal     41.923k (± 3.5%) i/s   (23.85 μs/i) -    211.224k in   5.038330s
Atomic Ruby Atomic Condition Variable Wait/Signal     40.666k (± 3.8%) i/s   (24.59 μs/i) -    206.650k in   5.081595s

Comparison:
      Synchronized Condition Variable Wait/Signal:    41923.4 i/s
Atomic Ruby Atomic Condition Variable Wait/Signal:    40666.4 i/s - same-ish: difference falls within error
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
atomic-ruby version: 0.15.5

Warming up --------------------------------------
      Synchronized Queue Push/Pop   184.000 i/100ms
Atomic Ruby Atomic Queue Push/Pop   149.000 i/100ms
Calculating -------------------------------------
      Synchronized Queue Push/Pop      1.819k (± 2.0%) i/s  (549.73 μs/i) -      9.200k in   5.057550s
Atomic Ruby Atomic Queue Push/Pop      1.493k (± 1.9%) i/s  (669.87 μs/i) -      7.599k in   5.090319s

Comparison:
      Synchronized Queue Push/Pop:     1819.1 i/s
Atomic Ruby Atomic Queue Push/Pop:     1492.8 i/s - 1.22x  slower

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
```

```
> bundle exec rake clobber && bundle exec rake compile && bundle exec ruby examples/atomic_thread_pool_benchmark.rb

ruby version:            ruby 4.0.6 (2026-07-14 revision 03b6d3f889) +YJIT +PRISM [arm64-darwin23]
concurrent-ruby version: 1.3.8
atomic-ruby version:     0.15.5

Fixed Pool Results:
Concurrent Ruby Fixed Thread Pool: 5.05313 seconds
Atomic Ruby Fixed Thread Pool:     4.753026 seconds

Adaptive Pool Results:
Concurrent Ruby IO Thread Pool:   0.221072 seconds
Atomic Ruby Adaptive Thread Pool: 0.233328 seconds
```

</details>

<details>

<summary>AtomicCountDownLatch</summary>

<br>

```ruby
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
```

```
> bundle exec rake clobber && bundle exec rake compile && bundle exec ruby examples/atomic_count_down_latch_benchmark.rb

ruby version:            ruby 4.0.6 (2026-07-14 revision 03b6d3f889) +YJIT +PRISM [arm64-darwin23]
concurrent-ruby version: 1.3.8
atomic-ruby version:     0.15.5

Benchmark Results:
Concurrent Ruby Count Down Latch:    0.000511 CPU seconds, 2.001465 elapsed seconds
Atomic Ruby Atomic Count Down Latch: 0.023529 CPU seconds, 2.00364 elapsed seconds
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
