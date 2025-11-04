# frozen_string_literal: true

require "mkmf"

append_cflags("-fvisibility=hidden")

create_makefile("atomic_ruby/atomic_ruby")
