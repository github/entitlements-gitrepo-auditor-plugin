# frozen_string_literal: true

require_relative "lib/version"

Gem::Specification.new do |s|
  s.name = "entitlements-gitrepo-auditor-plugin"
  s.version = Entitlements::Version::VERSION
  s.summary = "Entitlements GitRepo Auditor"
  s.description = "Entitlements plugin for a robust audit log"
  s.authors = ["GitHub, Inc. Security Ops"]
  s.email = "opensource+entitlements-app@github.com"
  s.license = "MIT"
  s.files = Dir.glob("lib/**/*")
  s.homepage = "https://github.com/github/entitlements-gitrepo-auditor-plugin"
  s.executables = %w[]

  s.add_dependency "contracts", "~> 0.17"
  s.add_dependency "entitlements-app", "~> 1.0"

  s.add_development_dependency "debug", "<= 1.8.0"
  s.add_development_dependency "rake", "~> 13.2", ">= 13.2.1"
  s.add_development_dependency "rspec", "= 3.8.0"
  s.add_development_dependency "rubocop", "~> 1.64"
  s.add_development_dependency "rubocop-github", "~> 0.20"
  s.add_development_dependency "rubocop-performance", "~> 1.21"
  s.add_development_dependency "rugged", "~> 1.7", ">= 1.7.2"
  s.add_development_dependency "simplecov", "~> 0.22.0"
  s.add_development_dependency "simplecov-erb", "~> 1.0", ">= 1.0.1"
  s.add_development_dependency "vcr", "~> 6.2"
  s.add_development_dependency "webmock", "~> 3.23", ">= 3.23.1"
end
