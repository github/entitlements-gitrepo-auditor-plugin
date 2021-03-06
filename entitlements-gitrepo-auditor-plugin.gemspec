# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name = "entitlements-gitrepo-auditor-plugin"
  s.version = File.read("VERSION").chomp
  s.summary = "Entitlements GitRepo Auditor"
  s.description = ""
  s.authors = ["GitHub, Inc. Security Ops"]
  s.email = "opensource+entitlements-app@github.com"
  s.license = "MIT"
  s.files = Dir.glob("lib/**/*") + %w[VERSION]
  s.homepage = "https://github.com/github/entitlements-gitrepo-auditor-plugin"
  s.executables = %w[]

  s.add_dependency "concurrent-ruby", "= 1.1.9"
  s.add_dependency "contracts", "= 0.16.0"
  s.add_dependency "faraday", ">= 0.17.3", "< 0.18"
  s.add_dependency "net-ldap", "~> 0.17.0"
  s.add_dependency "octokit", "~> 4.18"
  s.add_dependency "optimist", "= 3.0.0"

  s.add_development_dependency "contracts-rspec", "= 0.1.0"
  s.add_development_dependency "entitlements", "0.1.5.g6c8e3a79"
  s.add_development_dependency "rake", "= 13.0.6"
  s.add_development_dependency "rspec", "= 3.8.0"
  s.add_development_dependency "rspec-core", "= 3.8.0"
  s.add_development_dependency "rubocop", "= 1.29.1"
  s.add_development_dependency "rubocop-github", "= 0.17.0"
  s.add_development_dependency "rubocop-performance", "= 1.13.3"
  s.add_development_dependency "rugged", "= 0.27.5"
  s.add_development_dependency "simplecov", "= 0.16.1"
  s.add_development_dependency "simplecov-erb", "= 0.1.1"
  s.add_development_dependency "vcr", "= 4.0.0"
  s.add_development_dependency "webmock", "3.4.2"
end
