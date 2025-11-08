# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"
require "rake/extensiontask"

GEMSPEC = Gem::Specification.load("atomic_ruby.gemspec")

Minitest::TestTask.create

Rake::ExtensionTask.new("atomic_ruby", GEMSPEC) do |ext|
  ext.lib_dir = "lib/atomic_ruby"
end

namespace :rbs do
  task :generate do
    puts
    sh "rm -rf sig && rbs-inline --opt-out --output lib && echo"
  end
end

task build: %i[compile rbs:generate]
task default: %i[clobber compile rbs:generate test]
