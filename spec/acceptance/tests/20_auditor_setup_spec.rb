# frozen_string_literal: true

require_relative "spec_helper"

describe Entitlements do
  let(:basedn) { "ou=Expiration,ou=Entitlements,ou=Groups,dc=kittens,dc=net" }

  before(:all) do
    @result = run("auditor_setup", ["--debug"])
  end

  it "returns success" do
    expect(@result.success?).to eq(true)
  end

  it "prints nothing on STDOUT" do
    expect(@result.stdout).to eq("")
  end

  it "logs appropriate debug messages to STDERR for enabling the auditor" do
    expect(@result.stderr).to match(log("DEBUG", Regexp.escape("Entitlements::Auditor::GitRepo: Execute: git clone")))
    expect(@result.stderr).to match(log("DEBUG", Regexp.escape("Entitlements::Auditor::GitRepo: Execute: git config")))
  end

  it "logs appropriate debug messages to STDERR for auditor" do
    expect(@result.stderr).to match(log("DEBUG", Regexp.escape("Entitlements::Auditor::GitRepo: Valid change (create dc=net/dc=kittens/ou=Groups/ou=Entitlements/ou=Expiration/cn=empty) queued")))
    expect(@result.stderr).to match(log("DEBUG", Regexp.escape("Entitlements::Auditor::GitRepo: Valid change (create dc=net/dc=kittens/ou=Groups/ou=Entitlements/ou=Expiration/cn=expired) queued")))
    expect(@result.stderr).to match(log("DEBUG", Regexp.escape("Entitlements::Auditor::GitRepo: Valid change (create dc=net/dc=kittens/ou=Groups/ou=Entitlements/ou=Expiration/cn=full) queued")))
    expect(@result.stderr).to match(log("DEBUG", Regexp.escape("Entitlements::Auditor::GitRepo: Valid change (create dc=net/dc=kittens/ou=Groups/ou=Entitlements/ou=Expiration/cn=partial) queued")))
    expect(@result.stderr).to match(log("DEBUG", Regexp.escape("Entitlements::Auditor::GitRepo: Valid change (create dc=net/dc=kittens/ou=Groups/ou=Entitlements/ou=Expiration/cn=wildcard) queued")))
    expect(@result.stderr).to match(log("DEBUG", Regexp.escape("Entitlements::Auditor::GitRepo: Execute: git add dc\\=net/dc\\=kittens/ou\\=Groups/ou\\=Entitlements/ou\\=Expiration/cn\\=wildcard")))
    expect(@result.stderr).to match(log("DEBUG", "Entitlements::Auditor::GitRepo: Execute: git commit -m"))
    expect(@result.stderr).to match(log("DEBUG", "Audit Entitlements::Auditor::GitRepo completed successfully"))
  end

  it "does not record any auditor sync commits" do
    expect(@result.stderr).to match(log("DEBUG", "Entitlements::Auditor::GitRepo: Execute: git commit -m \\\\\\[sync\\\\ commit\\\\\\]"))
    expect(@result.stderr).to match(log("WARN", "Entitlements::Auditor::GitRepo: Sync change"))
  end
end
