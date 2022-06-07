# frozen_string_literal: true

require_relative "spec_helper"

describe Entitlements do
  let(:basedn) { "ou=Expiration,ou=Entitlements,ou=Groups,dc=kittens,dc=net" }

  before(:all) do
    @result = run("auditor_changes", ["--debug"])
  end

  it "returns success" do
    expect(@result.success?).to eq(true)
  end

  it "prints nothing on STDOUT" do
    expect(@result.stdout).to eq("")
  end

  it "records no changes" do
    expect(@result.stderr).to match(log("INFO", "No changes to be made. You're all set, friend! :sparkles:"))
  end

  it "does not record any auditor sync commits" do
    expect(@result.stderr).not_to match(log("DEBUG", "Entitlements::Auditor::GitRepo: Execute: git commit -m \\\\\\[sync\\\\ commit\\\\\\]"))
    expect(@result.stderr).not_to match(log("WARN", "Entitlements::Auditor::GitRepo: Sync change"))
    expect(@result.stderr).not_to match(log("DEBUG", "Entitlements::Auditor::GitRepo: Valid change"))
  end
end
