require_relative "lib/flappy/version"

Gem::Specification.new do |spec|
  spec.name = "flappy-rails"
  spec.version = Flappy::VERSION
  spec.authors = ["Jay Killeen", "Vanessa Soares"]

  spec.summary = "A flaky network for your Rails test suite. Can your signal make it through the pipes?"
  spec.description = "Flappy Rails puts a pipe between your tests and your app that drops, delays, throttles " \
                     "and flaps connections on a loop. Play it level by level, run your suite against it a " \
                     "hundred times, and see how far it gets. Pure Ruby, no dependencies."
  spec.homepage = "https://github.com/retail-tasker/flappy-rails"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["{lib,exe}/**/*", "LICENSE", "README.md", "CHANGELOG.md"]
  spec.bindir = "exe"
  spec.executables = ["flappy"]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "minitest", ">= 5.18"
  spec.add_development_dependency "rake", ">= 13.0"
end
