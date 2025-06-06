# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"

Minitest::TestTask.create

require "rake/extensiontask"

task build: :compile

GEMSPEC = Gem::Specification.load("atomic_ruby.gemspec")

Rake::ExtensionTask.new("atomic_ruby", GEMSPEC) do |ext|
  ext.lib_dir = "lib/atomic-ruby"
end

task default: %i[clobber compile test]
