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

  it "logs appropriate debug messages to STDERR for auditor" do
    expect(@result.stderr).to match(log("DEBUG", Regexp.escape("Entitlements::Auditor::GitRepo: Valid change (update dc=net/dc=kittens/ou=Groups/ou=Entitlements/ou=Expiration/cn=wildcard) queued")))
    expect(@result.stderr).to match(log("DEBUG", Regexp.escape("Entitlements::Auditor::GitRepo: Valid change (create dc=net/dc=kittens/ou=Groups/ou=Entitlements/ou=Expiration/cn=new) queued")))
    expect(@result.stderr).to match(log("DEBUG", Regexp.escape("Entitlements::Auditor::GitRepo: Valid change (delete dc=net/dc=kittens/ou=Groups/ou=Entitlements/ou=Expiration/cn=partial) queued")))
    expect(@result.stderr).to match(log("DEBUG", Regexp.escape("Entitlements::Auditor::GitRepo: Execute: git add dc\\=net/dc\\=kittens/ou\\=Groups/ou\\=Entitlements/ou\\=Expiration/cn\\=wildcard")))
    expect(@result.stderr).to match(log("DEBUG", "Entitlements::Auditor::GitRepo: Execute: git commit -m"))
    expect(@result.stderr).to match(log("DEBUG", "Audit Entitlements::Auditor::GitRepo completed successfully"))
  end

  it "does not record any auditor sync commits" do
    expect(@result.stderr).not_to match(log("DEBUG", "Entitlements::Auditor::GitRepo: Execute: git commit -m \\\\\\[sync\\\\ commit\\\\\\]"))
    expect(@result.stderr).not_to match(log("WARN", "Entitlements::Auditor::GitRepo: Sync change"))
  end

  context "verifying GitRepo auditor" do
    let(:dir) { ENV["GIT_REPO_CHECKOUT_DIRECTORY"] }
    let(:repo) { Rugged::Repository.new(dir) }
    let(:commits) do
      walker = Rugged::Walker.new(repo)
      walker.sorting(Rugged::SORT_TOPO | Rugged::SORT_REVERSE)
      walker.push(repo.head.target_id)
      walker.to_a
    end

    it "creates the expected commits with their messages" do
      expect(commits.size).to eq(5), commits.inspect
      expect(commits[0].message).to eq("initialize repo\n")
      expect(commits[2].message).to eq("[sync commit] gitrepo-auditor\n")
    end

    it "creates the correct tree with the valid commit" do
      tree = commits[2].tree
      expect(tree.count).to eq(1)
      expect(tree.count_recursive).to eq(1)
    end

    it "creates the correct files (representative sampling)" do
      pending "Write this test"
      system "ls -lR #{dir} 1>&2"
      expect(false).to eq(true)
    end
  end
end
