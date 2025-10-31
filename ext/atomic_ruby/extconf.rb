# frozen_string_literal: true

require "mkmf"

# Makes all symbols private by default to avoid unintended conflict
# with other gems. To explicitly export symbols you can use RUBY_FUNC_EXPORTED
# selectively, or entirely remove this flag.
append_cflags("-fvisibility=hidden")

if Ractor.respond_to?(:shareable_proc)
  $defs << "-DHAVE_RACTOR_SHAREABLE_PROC"
end

create_makefile("atomic_ruby/atomic_ruby")
