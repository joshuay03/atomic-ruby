# frozen_string_literal: true

require_relative "lib/atomic-ruby/version"

Gem::Specification.new do |spec|
  spec.name = "atomic-ruby"
  spec.version = AtomicRuby::VERSION
  spec.authors = ["Joshua Young"]
  spec.email = ["djry1999@gmail.com"]

  spec.summary = "Atomic primitives for Ruby"
  spec.homepage = "https://github.com/joshuay03/atomic-ruby"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir["lib/**/*", "ext/**/*", "**/*.{gemspec,md,txt}"]
  spec.require_paths = ["lib"]
  spec.extensions = ["ext/atomic_ruby/extconf.rb"]
end
