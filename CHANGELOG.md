## [Unreleased]

- Use `require` instead of `require_relative` for loading native extension

## [0.6.1] - 2025-10-15

- Exclude pre-compiled native extensions from gem files

## [0.6.0] - 2025-10-15

- Make `Atom`, `AtomicBoolean`, and `AtomicCountDownLatch` Ractor shareable

## [0.5.1] - 2025-07-26

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
