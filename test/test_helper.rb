# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "atomic-ruby"

require "minitest/autorun"

puts "\nEnabling GC stress mode...\n\n"
GC.stress = true
