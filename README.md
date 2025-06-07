# AtomicRuby

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
p atom.value # => 0
atom.swap { |current_value| current_value + 1 }
p atom.value # => 1
atom.swap { |current_value| current_value + 1 }
p atom.value # => 2
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

## Benchmarks

<details>

<summary>AtomicRuby::Atom</summary>

<br>

```ruby
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
    sleep(rand(0.1..0.2))
    @balance.swap { |current| current + amount }
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
    sleep(rand(0.1..0.2))
    @balance.swap { |current| current + amount }
  end
end

class SynchronizedBankAccount
  attr_reader :balance

  def initialize(balance)
    @balance = balance
    @mutex = Mutex.new
  end

  def deposit(amount)
    sleep(rand(0.1..0.2))
    @mutex.synchronize do
      @balance += amount
    end
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
```

```
> bundle exec rake compile && bundle exec ruby examples/atom_benchmark.rb

ruby version:            ruby 3.4.4 (2025-05-14 revision a38531fd3f) +YJIT +PRISM [arm64-darwin24]
concurrent-ruby version: 1.3.5
atomic-ruby version:     0.1.0

Balances:
Synchronized Bank Account Balance:           49995100
Concurrent Ruby Atomic Bank Account Balance: 49995100
Atomic Ruby Atomic Bank Account Balance:     49995100

Benchmark Results:
Synchronized Bank Account:           1.900873 seconds
Concurrent Ruby Atomic Bank Account: 1.840683 seconds
Atomic Ruby Atomic Bank Account:     1.755343 seconds
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
```

```
> bundle exec rake compile && bundle exec ruby examples/atomic_thread_pool_benchmark.rb

ruby version:            ruby 3.4.4 (2025-05-14 revision a38531fd3f) +YJIT +PRISM [arm64-darwin24]
concurrent-ruby version: 1.3.5
atomic-ruby version:     0.1.0

Benchmark Results:
Concurrent Ruby Thread Pool:    1.133100 seconds
Atomic Ruby Atomic Thread Pool: 1.088543 seconds
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
