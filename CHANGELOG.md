## [Unreleased]

- Revert `wrap_struct_name` back to `AtomicRuby::Atom`

## [0.5.0] - 2025-07-17

- Add shortcut aliases for `AtomicRuby` namespaced classes

## [0.4.0] - 2025-07-06

- Revert "Fix `AtomicThreadPool#<<` shutdown check race condition"
- Add `:name` to `AtomicThreadPool` initializer
- Add `AtomicCountDownLatch`

## [0.3.2] - 2025-06-14

- Fix `AtomicThreadPool#<<` shutdown check race condition

## [0.3.1] - 2025-06-08

- Fix current queue being mutated in `AtomicThreadPool#<<`

## [0.3.0] - 2025-06-08

- Add `AtomicBoolean`

## [0.2.0] - 2025-06-07

- Add `AtomicThreadPool`
- Require ruby >= 3.3
- Make `Atom#value` atomic

## [0.1.0] - 2025-06-06

- Initial release
