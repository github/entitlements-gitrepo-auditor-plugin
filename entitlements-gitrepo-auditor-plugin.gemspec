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
  s.add_dependency "entitlements-app", "~> 0.3"

  s.add_development_dependency "rake", "= 13.1.0"
  s.add_development_dependency "rspec", "= 3.13.0"
  s.add_development_dependency "rspec-core", "= 3.13.0"
  s.add_development_dependency "rubocop", "= 1.62.1"
  s.add_development_dependency "rubocop-github", "= 0.20.0"
  s.add_development_dependency "rubocop-performance", "= 1.20.2"
  s.add_development_dependency "rugged", "~> 1.7", ">= 1.7.2"
  s.add_development_dependency "simplecov", "= 0.22.0"
  s.add_development_dependency "simplecov-erb", "= 1.0.1"
  s.add_development_dependency "vcr", "= 6.2.0"
  s.add_development_dependency "webmock", "3.23.0"
end
