# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "atomic-ruby"

require "minitest/autorun"

Warning[:experimental] = false

if ENV["CI"]
  puts "\nEnabling GC stress mode...\n\n"
  GC.stress = true
end
