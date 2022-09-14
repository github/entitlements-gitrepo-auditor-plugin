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

  s.add_dependency "entitlements", "0.2.0"
  s.add_dependency "contracts", "0.17"

  s.add_development_dependency "rake", "= 13.0.6"
  s.add_development_dependency "rspec", "= 3.8.0"
  s.add_development_dependency "rspec-core", "= 3.8.0"
  s.add_development_dependency "rubocop", "= 1.29.1"
  s.add_development_dependency "rubocop-github", "= 0.17.0"
  s.add_development_dependency "rubocop-performance", "= 1.13.3"
  s.add_development_dependency "rugged", "= 0.27.5"
  s.add_development_dependency "simplecov", "= 0.16.1"
  s.add_development_dependency "simplecov-erb", "= 1.0.1"
  s.add_development_dependency "vcr", "= 4.0.0"
  s.add_development_dependency "webmock", "3.4.2"
end
