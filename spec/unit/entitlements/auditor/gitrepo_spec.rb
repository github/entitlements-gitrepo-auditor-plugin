# frozen_string_literal: true

require_relative "../../spec_helper"
require "tempfile"
require "tmpdir"

describe Entitlements::Auditor::GitRepo do
  let(:checkout_directory) { "/tmp/eofijsdlfkklsdfjoeifjsldkfjdfweioruwfsdflkj" }

  let(:base_config) do
    {
      "checkout_directory" => checkout_directory,
      "commit_message"     => "Foo",
      "description"        => "The neat GitHub repo",
      "git_name"           => "Hubot",
      "git_email"          => "hubot@github.com",
      "repo"               => "kittens/entitlements-audit",
      "sshkey"             => "YXNkZmFzZmRhc2Rm" # Base64 encoded "asdfasfdasdf"
    }
  end
  let(:config) { base_config }

  let(:logger) { instance_double(Logger) }
  let(:subject) { described_class.new(logger, config) }

  describe "#setup" do
    it "requests a clone when the checkout directory does not exist" do
      allow(subject).to receive(:validate_options!)
      allow(File).to receive(:directory?).with(checkout_directory).and_return(false)

      gitrepo = instance_double(Entitlements::Util::GitRepo)
      expect(Entitlements::Util::GitRepo).to receive(:new)
        .with(repo: "kittens/entitlements-audit", sshkey: "asdfasfdasdf", logger: anything)
        .and_return(gitrepo)
      expect(gitrepo).to receive(:clone).with(checkout_directory)
      expect(gitrepo).to receive(:configure).with(checkout_directory, "Hubot", "hubot@github.com")

      expect(logger).to receive(:debug).with("Entitlements::Auditor::GitRepo: Preparing #{checkout_directory}")
      expect(logger).to receive(:debug).with("Entitlements::Auditor::GitRepo: Directory #{checkout_directory} prepared")

      subject.setup
    end

    it "requests a pull when the checkout directory exists" do
      allow(subject).to receive(:validate_options!)
      allow(File).to receive(:directory?).with(checkout_directory).and_return(true)

      gitrepo = instance_double(Entitlements::Util::GitRepo)
      expect(Entitlements::Util::GitRepo).to receive(:new)
        .with(repo: "kittens/entitlements-audit", sshkey: "asdfasfdasdf", logger: anything)
        .and_return(gitrepo)
      expect(gitrepo).to receive(:pull).with(checkout_directory)
      expect(gitrepo).to receive(:configure).with(checkout_directory, "Hubot", "hubot@github.com")

      expect(logger).to receive(:debug).with("Entitlements::Auditor::GitRepo: Preparing #{checkout_directory}")
      expect(logger).to receive(:debug).with("Entitlements::Auditor::GitRepo: Directory #{checkout_directory} prepared")

      subject.setup
    end
  end

  describe "#commit" do
    before(:each) do
      @logger = instance_double(Logger)

      @tempdir = Dir.mktmpdir

      @repo = instance_double(Entitlements::Util::GitRepo)

      @subject = described_class.new(@logger, config)
      @subject.instance_variable_set("@repo", @repo)
      allow(@subject).to receive(:checkout_directory).and_return(@tempdir)
      expect(@subject).to receive(:update_files)

      @action1 = instance_double(Entitlements::Models::Action)
      allow(@action1).to receive(:dn).and_return("cn=group1,ou=foo,dc=kittens,dc=net")
    end

    after(:each) do
      FileUtils.remove_entry_secure(@tempdir) if File.directory?(@tempdir)
    end

    context "with provider exception" do
      let(:exc) { RuntimeError.new("provider boo-boo") }

      context "with sync changes" do
        context "with valid changes" do
          it "calls commit_changes for valid changes and skips sync changes" do
            sync_change_hash = {
              File.join(@tempdir, "foo/bar/baz.txt") => "foo\nbar\nbaz\n",
              File.join(@tempdir, "foo/bar/foo.txt") => "FOO\nBAR\nBAZ\n"
            }
            valid_change_hash = {
              File.join(@tempdir, "fizz/bar/baz.txt") => "foo\nbar\nbaz\n",
              File.join(@tempdir, "fizz/bar/foo.txt") => "FOO\nBAR\nBAZ\n",
              File.join(@tempdir, "fizz/bar/bar.txt") => "FOO\nBAR\nBAZ\n"
            }
            allow(@subject).to receive(:delete_files) do |args|
              args[:sync_changes].merge!(sync_change_hash)
              args[:valid_changes].merge!(valid_change_hash)
            end
            expect(@logger).to receive(:warn).with("Entitlements::Auditor::GitRepo: Not committing 2 unrecognized change(s) due to provider exception")
            expect(@logger).to receive(:debug).with("Entitlements::Auditor::GitRepo: Committing 3 change(s) to git repository")
            expect(@subject).to receive(:commit_changes).with(valid_change_hash, :valid, "Foo")
            expect(@subject).not_to receive(:commit_changes).with(sync_change_hash, :sync, "Foo")
            @subject.commit(actions: [], successful_actions: Set.new, provider_exception: exc)
          end
        end

        context "with no valid changes" do
          it "does not call commit_changes" do
            sync_change_hash = {
              File.join(@tempdir, "foo/bar/baz.txt") => "foo\nbar\nbaz\n",
              File.join(@tempdir, "foo/bar/foo.txt") => "FOO\nBAR\nBAZ\n"
            }
            allow(@subject).to receive(:delete_files) do |args|
              args[:sync_changes].merge!(sync_change_hash)
            end
            expect(@logger).to receive(:warn).with("Entitlements::Auditor::GitRepo: Not committing 2 unrecognized change(s) due to provider exception")
            expect(@subject).not_to receive(:commit_changes)
            @subject.commit(actions: [], successful_actions: Set.new, provider_exception: exc)
          end
        end
      end

      context "with no sync changes" do
        context "with valid changes" do
          it "calls commit_changes once for valid changes" do
            valid_change_hash = {
              File.join(@tempdir, "foo/bar/baz.txt") => "foo\nbar\nbaz\n",
              File.join(@tempdir, "foo/bar/foo.txt") => "FOO\nBAR\nBAZ\n"
            }
            allow(@subject).to receive(:delete_files) do |args|
              args[:valid_changes].merge!(valid_change_hash)
            end
            expect(@logger).to receive(:debug).with("Entitlements::Auditor::GitRepo: Committing 2 change(s) to git repository")
            expect(@subject).to receive(:commit_changes).with(valid_change_hash, :valid, "Foo")
            @subject.commit(actions: [], successful_actions: Set.new, provider_exception: exc)
          end
        end
      end
    end

    context "without provider exception" do
      let(:exc) { nil }

      context "with sync changes" do
        context "with valid changes" do
          it "calls commit_changes once for sync changes and once for valid changes" do
            sync_change_hash = {
              File.join(@tempdir, "foo/bar/baz.txt") => "foo\nbar\nbaz\n",
              File.join(@tempdir, "foo/bar/foo.txt") => "FOO\nBAR\nBAZ\n"
            }
            valid_change_hash = {
              File.join(@tempdir, "fizz/bar/baz.txt") => "foo\nbar\nbaz\n",
              File.join(@tempdir, "fizz/bar/foo.txt") => "FOO\nBAR\nBAZ\n",
              File.join(@tempdir, "fizz/bar/bar.txt") => "FOO\nBAR\nBAZ\n"
            }
            allow(@subject).to receive(:delete_files) do |args|
              args[:sync_changes].merge!(sync_change_hash)
              args[:valid_changes].merge!(valid_change_hash)
            end
            expect(@logger).to receive(:warn).with("Entitlements::Auditor::GitRepo: Sync changes required: count=2")
            expect(@logger).to receive(:debug).with("Entitlements::Auditor::GitRepo: Committing 3 change(s) to git repository")
            expect(@subject).to receive(:commit_changes).with(valid_change_hash, :valid, "Foo")
            expect(@subject).to receive(:commit_changes).with(sync_change_hash, :sync, "Foo")
            @subject.commit(actions: [], successful_actions: Set.new, provider_exception: exc)
          end
        end

        context "with no valid changes" do
          it "calls commit_changes once for sync changes" do
            sync_change_hash = {
              File.join(@tempdir, "foo/bar/baz.txt") => "foo\nbar\nbaz\n",
              File.join(@tempdir, "foo/bar/foo.txt") => "FOO\nBAR\nBAZ\n"
            }
            allow(@subject).to receive(:delete_files) do |args|
              args[:sync_changes].merge!(sync_change_hash)
            end
            expect(@logger).to receive(:warn).with("Entitlements::Auditor::GitRepo: Sync changes required: count=2")
            expect(@subject).to receive(:commit_changes).with(sync_change_hash, :sync, "Foo")
            @subject.commit(actions: [], successful_actions: Set.new, provider_exception: exc)
          end
        end
      end

      context "with no sync changes" do
        context "with valid changes" do
          it "calls commit_changes once for valid changes" do
            valid_change_hash = {
              File.join(@tempdir, "foo/bar/baz.txt") => "foo\nbar\nbaz\n",
              File.join(@tempdir, "foo/bar/foo.txt") => "FOO\nBAR\nBAZ\n"
            }
            allow(@subject).to receive(:delete_files) do |args|
              args[:valid_changes].merge!(valid_change_hash)
            end
            expect(@logger).to receive(:debug).with("Entitlements::Auditor::GitRepo: Committing 2 change(s) to git repository")
            expect(@subject).to receive(:commit_changes).with(valid_change_hash, :valid, "Foo")
            @subject.commit(actions: [], successful_actions: Set.new, provider_exception: exc)
          end
        end

        context "with no valid changes" do
          it "calls the push method without doing anything else" do
            allow(@subject).to receive(:delete_files)
            expect(@logger).to receive(:debug).with("Entitlements::Auditor::GitRepo: No changes to git repository")
            @subject.commit(actions: [], successful_actions: Set.new, provider_exception: exc)
          end
        end
      end
    end
  end

  describe "#update_files" do
    let(:group1) { instance_double(Entitlements::Models::Group) }
    let(:group1_dn) { "cn=group1,ou=Groups,dc=kittens,dc=net" }
    let(:group1_members) { Set.new(["uid=russian-blue,dc=kittens,dc=net", "uid=snowshoe,dc=kittens,dc=net"]) }
    let(:group1_metadata) { { "team_name" => "group1", "team_id" => 1, "cat_color" => "brown" } }
    let(:group1_metadata_string) { "metadata_cat_color=brown\nmetadata_team_id=1\nmetadata_team_name=group1\n" }
    let(:group2) { instance_double(Entitlements::Models::Group) }
    let(:group2_dn) { "cn=group2,ou=Groups,dc=kittens,dc=net" }
    let(:group2_members) { Set.new(["uid=russian-blue,dc=kittens,dc=net"]) }
    let(:group2_metadata) { { "team_name" => "group2", "team_id" => 2, "cat_color" => "grey" } }
    let(:group2_metadata_string) { "metadata_cat_color=grey\nmetadata_team_id=2\nmetadata_team_name=group2\n" }
    let(:group3) { instance_double(Entitlements::Models::Group) }
    let(:group3_dn) { "cn=group3,ou=Groups,dc=kittens,dc=net" }
    let(:group3_members) { Set.new(["uid=snowshoe,dc=kittens,dc=net"]) }
    let(:group3_metadata) { { "team_name" => "group3", "team_id" => 3 } }
    let(:group3_metadata_string) { "metadata_team_id=3\nmetadata_team_name=group3\n" }
    let(:group4) { instance_double(Entitlements::Models::Group) }
    let(:group4_dn) { "cn=group4,ou=Groups,dc=kittens,dc=net" }
    let(:group4_members) { Set.new(["uid=tabby,dc=kittens,dc=net"]) }
    let(:group4_metadata) { { } }
    let(:group5) { instance_double(Entitlements::Models::Group) }
    let(:group5_dn) { "cn=group5,ou=Groups,dc=kittens,dc=net" }
    let(:group5_members) { Set.new(["uid=coon,dc=kittens,dc=net"]) }
    let(:group5_metadata) { { } }
    let(:group6) { instance_double(Entitlements::Models::Group) }
    let(:group6_dn) { "cn=group6,ou=Groups,dc=kittens,dc=net" }
    let(:group6_members) { Set.new(["uid=tabby,dc=kittens,dc=net", "uid=coon,dc=kittens,dc=net"]) }
    let(:group6_metadata) { { } }
    let(:action1) { instance_double(Entitlements::Models::Action) }
    let(:action2) { instance_double(Entitlements::Models::Action) }
    let(:action3) { instance_double(Entitlements::Models::Action) }
    let(:action4) { instance_double(Entitlements::Models::Action) }
    let(:action5) { instance_double(Entitlements::Models::Action) }
    let(:action6) { instance_double(Entitlements::Models::Action) }

    context "when everything matches" do
      let(:calc_hash) do
        {
          group1_dn => group1,
          group2_dn => group2,
          group3_dn => group3
        }
      end

      let(:action_hash) { {} }
      let(:successful_actions) { Set.new }

      it "preserves empty hash sync_changes and valid_changes" do
        allow(Entitlements::Data::Groups::Calculated).to receive(:to_h).and_return(calc_hash)

        allow(group1).to receive(:member_strings).and_return(group1_members)
        allow(group1).to receive(:metadata).and_return(group1_metadata)
        allow(group2).to receive(:member_strings).and_return(group2_members)
        allow(group2).to receive(:metadata).and_return(group2_metadata)
        allow(group3).to receive(:member_strings).and_return(Set.new)
        allow(group3).to receive(:metadata).and_return(group3_metadata)

        file1 = File.join(checkout_directory, "dc=net", "dc=kittens", "ou=Groups", "cn=group1")
        file2 = File.join(checkout_directory, "dc=net", "dc=kittens", "ou=Groups", "cn=group2")
        file3 = File.join(checkout_directory, "dc=net", "dc=kittens", "ou=Groups", "cn=group3")

        allow(File).to receive(:file?).with(file1).and_return(true)
        group1_contents = group1_members.sort.join("\n") + "\n" + group1_metadata_string
        allow(File).to receive(:read).with(file1).and_return(group1_contents)

        allow(File).to receive(:file?).with(file2).and_return(true)
        group2_contents = group2_members.sort.join("\n") + "\n" + group2_metadata_string
        allow(File).to receive(:read).with(file2).and_return(group2_contents)

        # Testing that an empty group with no corresponding audit file does not result in sync changes.
        allow(File).to receive(:file?).with(file3).and_return(false)

        sync_changes = {}
        valid_changes = {}

        subject.send(:update_files,
          action_hash:,
          successful_actions:,
          sync_changes:,
          valid_changes:
        )

        expect(sync_changes).to eq({})
        expect(valid_changes).to eq({})
      end
    end

    context "with only sync changes" do
      let(:calc_hash) do
        {
          group1_dn => group1,
          group2_dn => group2,
          group3_dn => group3
        }
      end

      let(:action_hash) { {} }
      let(:successful_actions) { Set.new }

      it "populates sync_changes and leaves valid_changes empty" do
        allow(Entitlements::Data::Groups::Calculated).to receive(:to_h).and_return(calc_hash)

        allow(group1).to receive(:member_strings).and_return(group1_members)
        allow(group1).to receive(:metadata).and_return(group1_metadata)
        allow(group2).to receive(:member_strings).and_return(group2_members)
        allow(group2).to receive(:metadata).and_return(group2_metadata)
        allow(group3).to receive(:member_strings).and_return(group3_members)
        allow(group3).to receive(:metadata).and_return(group3_metadata)

        file1 = File.join(checkout_directory, "dc=net", "dc=kittens", "ou=Groups", "cn=group1")
        file2 = File.join(checkout_directory, "dc=net", "dc=kittens", "ou=Groups", "cn=group2")
        file3 = File.join(checkout_directory, "dc=net", "dc=kittens", "ou=Groups", "cn=group3")

        allow(File).to receive(:file?).with(file1).and_return(true)
        group1_contents = group1_members.sort.join("\n") + "\n" + group1_metadata_string
        allow(File).to receive(:read).with(file1).and_return(group1_contents)

        allow(File).to receive(:file?).with(file2).and_return(false)

        allow(File).to receive(:file?).with(file3).and_return(true)
        allow(File).to receive(:read).with(file3).and_return("This is the wrong content")

        expect(logger).to receive(:warn)
          .with("Entitlements::Auditor::GitRepo: Sync change (create dc=net/dc=kittens/ou=Groups/cn=group2) required")

        expect(logger).to receive(:warn)
          .with("Entitlements::Auditor::GitRepo: Sync change (update dc=net/dc=kittens/ou=Groups/cn=group3) required")

        sync_changes = {}
        valid_changes = {}

        subject.send(:update_files,
          action_hash:,
          successful_actions:,
          sync_changes:,
          valid_changes:
        )

        expect(sync_changes).to eq(
          "dc=net/dc=kittens/ou=Groups/cn=group2" => "uid=russian-blue,dc=kittens,dc=net\nmetadata_cat_color=grey\nmetadata_team_id=2\nmetadata_team_name=group2\n",
          "dc=net/dc=kittens/ou=Groups/cn=group3" => "uid=snowshoe,dc=kittens,dc=net\nmetadata_team_id=3\nmetadata_team_name=group3\n"
        )
        expect(valid_changes).to eq({})
      end
    end

    context "with adding a file that was not there before" do
      let(:calc_hash) do
        {
          group1_dn => group1,
          group2_dn => group2,
          group3_dn => group3,
          group4_dn => group4
        }
      end

      let(:action_hash) { { group1_dn => action1, group2_dn => action2, group3_dn => action3, group4_dn => action4 } }
      let(:successful_actions) { Set.new([group1_dn, group3_dn]) }

      it "populates sync_changes and valid_changes" do
        allow(Entitlements::Data::Groups::Calculated).to receive(:to_h).and_return(calc_hash)

        file1 = File.join(checkout_directory, "dc=net", "dc=kittens", "ou=Groups", "cn=group1")
        file2 = File.join(checkout_directory, "dc=net", "dc=kittens", "ou=Groups", "cn=group2")
        file3 = File.join(checkout_directory, "dc=net", "dc=kittens", "ou=Groups", "cn=group3")
        file4 = File.join(checkout_directory, "dc=net", "dc=kittens", "ou=Groups", "cn=group4")

        allow(File).to receive(:file?).with(file1).and_return(true)
        group1_contents = group1_members.sort.join("\n") + "\n" + group1_metadata_string
        allow(File).to receive(:read).with(file1).and_return(group1_contents)

        allow(File).to receive(:file?).with(file2).and_return(true)
        group2_contents = group2_members.sort.join("\n") + "\n" + group2_metadata_string
        allow(File).to receive(:read).with(file2).and_return(group2_contents)

        allow(File).to receive(:file?).with(file3).and_return(false)
        allow(File).to receive(:file?).with(file4).and_return(false)

        allow(group1).to receive(:member_strings).and_return(group1_members)
        allow(group1).to receive(:metadata).and_return(group1_metadata)
        allow(group2).to receive(:member_strings).and_return(group2_members)
        allow(group2).to receive(:metadata).and_return(group2_metadata)
        allow(group3).to receive(:member_strings).and_return(group3_members)
        allow(group3).to receive(:metadata).and_return(group3_metadata)
        allow(group4).to receive(:member_strings).and_return(group4_members)
        allow(group4).to receive(:metadata).and_return(group4_metadata)

        allow(action1).to receive(:change_type).and_return(:add)
        allow(action2).to receive(:change_type).and_return(:add)
        allow(action3).to receive(:change_type).and_return(:add)
        allow(action4).to receive(:change_type).and_return(:add)

        sync_changes = {}
        valid_changes = {}

        expect(logger).to receive(:warn)
          .with("Entitlements::Auditor::GitRepo: Sync change (delete dc=net/dc=kittens/ou=Groups/cn=group1) required")
        expect(logger).to receive(:warn)
          .with("Entitlements::Auditor::GitRepo: Skip sync change (delete dc=net/dc=kittens/ou=Groups/cn=group2) due to unsuccessful action")
        expect(logger).to receive(:warn)
          .with("Entitlements::Auditor::GitRepo: Skip change (add dc=net/dc=kittens/ou=Groups/cn=group2) due to unsuccessful action")
        expect(logger).to receive(:warn)
          .with("Entitlements::Auditor::GitRepo: Skip change (add dc=net/dc=kittens/ou=Groups/cn=group4) due to unsuccessful action")
        expect(logger).to receive(:debug)
          .with("Entitlements::Auditor::GitRepo: Valid change (create dc=net/dc=kittens/ou=Groups/cn=group1) queued")
        expect(logger).to receive(:debug)
          .with("Entitlements::Auditor::GitRepo: Valid change (create dc=net/dc=kittens/ou=Groups/cn=group3) queued")

        subject.send(:update_files,
          action_hash:,
          successful_actions:,
          sync_changes:,
          valid_changes:
        )

        expect(sync_changes).to eq(
          "dc=net/dc=kittens/ou=Groups/cn=group1" => :delete
        )
        expect(valid_changes).to eq(
          "dc=net/dc=kittens/ou=Groups/cn=group1" => "uid=russian-blue,dc=kittens,dc=net\nuid=snowshoe,dc=kittens,dc=net\nmetadata_cat_color=brown\nmetadata_team_id=1\nmetadata_team_name=group1\n",
          "dc=net/dc=kittens/ou=Groups/cn=group3" => "uid=snowshoe,dc=kittens,dc=net\nmetadata_team_id=3\nmetadata_team_name=group3\n"
        )
      end
    end

    context "with updating a file" do
      let(:calc_hash) do
        {
          group1_dn => group1,
          group2_dn => group2,
          group3_dn => group3,
          group4_dn => group4,
          group5_dn => group5,
          group6_dn => group6
        }
      end

      let(:action_hash) do
        {
          group1_dn => action1,
          group2_dn => action2,
          group3_dn => action3,
          group4_dn => action4,
          group5_dn => action5,
          group6_dn => action6
        }
      end

      let(:successful_actions) { Set.new([group1_dn, group2_dn, group5_dn]) }

      it "populates sync_changes and valid_changes" do
        allow(Entitlements::Data::Groups::Calculated).to receive(:to_h).and_return(calc_hash)

        # [Happy path] Case 1: File exists, file contains correct existing members and metadata, action successful
        file1 = File.join(checkout_directory, "dc=net", "dc=kittens", "ou=Groups", "cn=group1")
        allow(File).to receive(:file?).with(file1).and_return(true)
        group1_existing = instance_double(Entitlements::Models::Group)
        group1_existing_members = Set.new(["uid=russian-blue,dc=kittens,dc=net"])
        allow(group1_existing).to receive(:member_strings).and_return(group1_existing_members)
        allow(group1_existing).to receive(:metadata).and_return(group1_metadata)
        allow(File).to receive(:read).with(file1).and_return(group1_existing_members.sort.join("\n") + "\n" + group1_metadata_string)
        allow(group1).to receive(:member_strings).and_return(group1_members)
        allow(group1).to receive(:metadata).and_return(group1_metadata)
        allow(action1).to receive(:change_type).and_return(:update)
        allow(action1).to receive(:existing).and_return(group1_existing)

        # [Sad path] Case 2: File exists, file contains wrong existing members, action successful
        file2 = File.join(checkout_directory, "dc=net", "dc=kittens", "ou=Groups", "cn=group2")
        allow(File).to receive(:file?).with(file2).and_return(true)
        allow(File).to receive(:read).with(file2).and_return("The wrong members\n")
        group2_existing = instance_double(Entitlements::Models::Group)
        group2_existing_members = Set.new(["uid=russian-blue,dc=kittens,dc=net"])
        allow(group2_existing).to receive(:member_strings).and_return(group2_existing_members)
        allow(group2_existing).to receive(:metadata).and_return(group2_metadata)
        allow(group2).to receive(:member_strings).and_return(group2_members)
        allow(group2).to receive(:metadata).and_return(group2_metadata)
        allow(action2).to receive(:change_type).and_return(:update)
        allow(action2).to receive(:existing).and_return(group2_existing)

        # [Sad path] Case 3: File exists, file contains correct existing members, action not successful
        file3 = File.join(checkout_directory, "dc=net", "dc=kittens", "ou=Groups", "cn=group3")
        allow(File).to receive(:file?).with(file3).and_return(true)
        group3_existing = instance_double(Entitlements::Models::Group)
        group3_existing_members = Set.new(["uid=tabby,dc=kittens,dc=net"])
        allow(group3_existing).to receive(:member_strings).and_return(group3_existing_members)
        allow(group3_existing).to receive(:metadata).and_return(group3_metadata)
        allow(group3).to receive(:member_strings).and_return(group3_members)
        allow(group3).to receive(:metadata).and_return(group3_metadata)
        allow(File).to receive(:read).with(file3).and_return(group3_existing_members.sort.join("\n") + "\n" + group3_metadata_string)
        allow(action3).to receive(:change_type).and_return(:update)
        allow(action3).to receive(:existing).and_return(group3_existing)

        # [Sad path] Case 4: File exists, file contains wrong existing members, action not successful
        file4 = File.join(checkout_directory, "dc=net", "dc=kittens", "ou=Groups", "cn=group4")
        allow(File).to receive(:file?).with(file4).and_return(true)
        allow(File).to receive(:read).with(file4).and_return("The wrong members\n")
        group4_existing = instance_double(Entitlements::Models::Group)
        group4_existing_members = Set.new(["uid=snowshoe,dc=kittens,dc=net"])
        allow(group4_existing).to receive(:member_strings).and_return(group4_existing_members)
        allow(group4_existing).to receive(:metadata).and_return(group4_metadata)
        allow(group4).to receive(:member_strings).and_return(group4_members)
        allow(group4).to receive(:metadata).and_return(group4_metadata)
        allow(action4).to receive(:change_type).and_return(:update)
        allow(action4).to receive(:existing).and_return(group4_existing)

        # [Sad path] Case 5: File does not exist, action successful
        file5 = File.join(checkout_directory, "dc=net", "dc=kittens", "ou=Groups", "cn=group5")
        allow(File).to receive(:file?).with(file5).and_return(false)
        group5_existing = instance_double(Entitlements::Models::Group)
        group5_existing_members = Set.new(["uid=snowshoe,dc=kittens,dc=net"])
        allow(group5_existing).to receive(:member_strings).and_return(group5_existing_members)
        allow(group5_existing).to receive(:metadata).and_return(group5_metadata)
        allow(group5).to receive(:member_strings).and_return(group5_members)
        allow(group5).to receive(:metadata).and_return(group5_metadata)
        allow(action5).to receive(:change_type).and_return(:update)
        allow(action5).to receive(:existing).and_return(group5_existing)

        # [Sad path] Case 6: File does not exist, action unsuccessful
        file6 = File.join(checkout_directory, "dc=net", "dc=kittens", "ou=Groups", "cn=group6")
        allow(File).to receive(:file?).with(file6).and_return(false)
        group6_existing = instance_double(Entitlements::Models::Group)
        group6_existing_members = Set.new(["uid=snowshoe,dc=kittens,dc=net"])
        allow(group6_existing).to receive(:member_strings).and_return(group6_existing_members)
        allow(group6_existing).to receive(:metadata).and_return(group6_metadata)
        allow(group6).to receive(:member_strings).and_return(group6_members)
        allow(group6).to receive(:metadata).and_return(group6_metadata)
        allow(action6).to receive(:change_type).and_return(:update)
        allow(action6).to receive(:existing).and_return(group6_existing)

        sync_changes = {}
        valid_changes = {}

        expect(logger).to receive(:warn)
          .with("Entitlements::Auditor::GitRepo: Sync change (update dc=net/dc=kittens/ou=Groups/cn=group2) required")
        expect(logger).to receive(:warn)
          .with("Entitlements::Auditor::GitRepo: Skip change (update dc=net/dc=kittens/ou=Groups/cn=group3) due to unsuccessful action")
        expect(logger).to receive(:warn)
          .with("Entitlements::Auditor::GitRepo: Skip sync change (update dc=net/dc=kittens/ou=Groups/cn=group4) due to unsuccessful action")
        expect(logger).to receive(:warn)
          .with("Entitlements::Auditor::GitRepo: Sync change (create dc=net/dc=kittens/ou=Groups/cn=group5) required")
        expect(logger).to receive(:warn)
          .with("Entitlements::Auditor::GitRepo: Skip sync change (create dc=net/dc=kittens/ou=Groups/cn=group6) due to unsuccessful action")
        expect(logger).to receive(:debug)
          .with("Entitlements::Auditor::GitRepo: Valid change (update dc=net/dc=kittens/ou=Groups/cn=group1) queued")
        expect(logger).to receive(:debug)
          .with("Entitlements::Auditor::GitRepo: Valid change (update dc=net/dc=kittens/ou=Groups/cn=group2) queued")
        expect(logger).to receive(:debug)
          .with("Entitlements::Auditor::GitRepo: Valid change (update dc=net/dc=kittens/ou=Groups/cn=group5) queued")

        subject.send(:update_files,
          action_hash:,
          successful_actions:,
          sync_changes:,
          valid_changes:
        )

        expect(sync_changes).to eq(
          "dc=net/dc=kittens/ou=Groups/cn=group2" => "uid=russian-blue,dc=kittens,dc=net\nmetadata_cat_color=grey\nmetadata_team_id=2\nmetadata_team_name=group2\n",
          "dc=net/dc=kittens/ou=Groups/cn=group5" => "uid=snowshoe,dc=kittens,dc=net\n"
        )
        expect(valid_changes).to eq(
          "dc=net/dc=kittens/ou=Groups/cn=group1" => "uid=russian-blue,dc=kittens,dc=net\nuid=snowshoe,dc=kittens,dc=net\nmetadata_cat_color=brown\nmetadata_team_id=1\nmetadata_team_name=group1\n",
          "dc=net/dc=kittens/ou=Groups/cn=group2" => "uid=russian-blue,dc=kittens,dc=net\nmetadata_cat_color=grey\nmetadata_team_id=2\nmetadata_team_name=group2\n",
          "dc=net/dc=kittens/ou=Groups/cn=group5" => "uid=coon,dc=kittens,dc=net\n"
        )
      end
    end

    context "with deleting a file" do
      let(:calc_hash) { {} }

      let(:action_hash) do
        {
          group1_dn => action1,
          group2_dn => action2,
          group3_dn => action3,
          group4_dn => action4,
          group5_dn => action5,
          group6_dn => action6
        }
      end

      let(:successful_actions) { Set.new([group1_dn, group2_dn, group5_dn]) }

      it "populates sync_changes and valid_changes" do
        allow(Entitlements::Data::Groups::Calculated).to receive(:to_h).and_return(calc_hash)

        # [Happy path] Case 1: File exists, file contains correct existing members, action successful
        file1 = File.join(checkout_directory, "dc=net", "dc=kittens", "ou=Groups", "cn=group1")
        allow(File).to receive(:file?).with(file1).and_return(true)
        group1_existing = instance_double(Entitlements::Models::Group)
        group1_existing_members = Set.new(["uid=russian-blue,dc=kittens,dc=net"])
        allow(group1_existing).to receive(:member_strings).and_return(group1_existing_members)
        allow(group1_existing).to receive(:metadata).and_return(group1_metadata)
        allow(File).to receive(:read).with(file1).and_return(group1_existing_members.sort.join("\n") + "\n" + group1_metadata_string)
        allow(group1).to receive(:member_strings).and_return(group1_members)
        allow(group1).to receive(:metadata).and_return(group1_metadata)
        allow(action1).to receive(:change_type).and_return(:delete)
        allow(action1).to receive(:existing).and_return(group1_existing)

        # [Sad path] Case 2: File exists, file contains wrong existing members, action successful
        file2 = File.join(checkout_directory, "dc=net", "dc=kittens", "ou=Groups", "cn=group2")
        allow(File).to receive(:file?).with(file2).and_return(true)
        allow(File).to receive(:read).with(file2).and_return("The wrong members\n")
        group2_existing = instance_double(Entitlements::Models::Group)
        group2_existing_members = Set.new(["uid=russian-blue,dc=kittens,dc=net"])
        allow(group2_existing).to receive(:member_strings).and_return(group2_existing_members)
        allow(group2_existing).to receive(:metadata).and_return(group2_metadata)
        allow(group2).to receive(:member_strings).and_return(group2_members)
        allow(group2).to receive(:metadata).and_return(group2_metadata)
        allow(action2).to receive(:change_type).and_return(:delete)
        allow(action2).to receive(:existing).and_return(group2_existing)

        # [Sad path] Case 3: File exists, file contains correct existing members, action not successful
        file3 = File.join(checkout_directory, "dc=net", "dc=kittens", "ou=Groups", "cn=group3")
        allow(File).to receive(:file?).with(file3).and_return(true)
        group3_existing = instance_double(Entitlements::Models::Group)
        group3_existing_members = Set.new(["uid=tabby,dc=kittens,dc=net"])
        allow(group3_existing).to receive(:member_strings).and_return(group3_existing_members)
        allow(group3_existing).to receive(:metadata).and_return(group3_metadata)
        allow(group3).to receive(:member_strings).and_return(group3_members)
        allow(group3).to receive(:metadata).and_return(group3_metadata)
        allow(File).to receive(:read).with(file3).and_return(group3_existing_members.sort.join("\n") + "\n" + group3_metadata_string)
        allow(action3).to receive(:change_type).and_return(:delete)
        allow(action3).to receive(:existing).and_return(group3_existing)

        # [Sad path] Case 4: File exists, file contains wrong existing members, action not successful
        file4 = File.join(checkout_directory, "dc=net", "dc=kittens", "ou=Groups", "cn=group4")
        allow(File).to receive(:file?).with(file4).and_return(true)
        allow(File).to receive(:read).with(file4).and_return("The wrong members\n")
        group4_existing = instance_double(Entitlements::Models::Group)
        group4_existing_members = Set.new(["uid=snowshoe,dc=kittens,dc=net"])
        allow(group4_existing).to receive(:member_strings).and_return(group4_existing_members)
        allow(group4_existing).to receive(:metadata).and_return(group4_metadata)
        allow(group4).to receive(:member_strings).and_return(group4_members)
        allow(group4).to receive(:metadata).and_return(group4_metadata)
        allow(action4).to receive(:change_type).and_return(:delete)
        allow(action4).to receive(:existing).and_return(group4_existing)

        # [Sad path] Case 5: File does not exist, action successful
        file5 = File.join(checkout_directory, "dc=net", "dc=kittens", "ou=Groups", "cn=group5")
        allow(File).to receive(:file?).with(file5).and_return(false)
        group5_existing = instance_double(Entitlements::Models::Group)
        group5_existing_members = Set.new(["uid=snowshoe,dc=kittens,dc=net"])
        allow(group5_existing).to receive(:member_strings).and_return(group5_existing_members)
        allow(group5_existing).to receive(:metadata).and_return(group5_metadata)
        allow(group5).to receive(:member_strings).and_return(group5_members)
        allow(group5).to receive(:metadata).and_return(group5_metadata)
        allow(action5).to receive(:change_type).and_return(:delete)
        allow(action5).to receive(:existing).and_return(group5_existing)

        # [Sad path] Case 6: File does not exist, action unsuccessful
        file6 = File.join(checkout_directory, "dc=net", "dc=kittens", "ou=Groups", "cn=group6")
        allow(File).to receive(:file?).with(file6).and_return(false)
        group6_existing = instance_double(Entitlements::Models::Group)
        group6_existing_members = Set.new(["uid=snowshoe,dc=kittens,dc=net"])
        allow(group6_existing).to receive(:member_strings).and_return(group6_existing_members)
        allow(group6_existing).to receive(:metadata).and_return(group6_metadata)
        allow(group6).to receive(:member_strings).and_return(group6_members)
        allow(group6).to receive(:metadata).and_return(group6_metadata)
        allow(action6).to receive(:change_type).and_return(:delete)
        allow(action6).to receive(:existing).and_return(group6_existing)

        sync_changes = {}
        valid_changes = {}

        expect(logger).to receive(:warn)
          .with("Entitlements::Auditor::GitRepo: Sync change (update dc=net/dc=kittens/ou=Groups/cn=group2) required")
        expect(logger).to receive(:warn)
          .with("Entitlements::Auditor::GitRepo: Skip change (delete dc=net/dc=kittens/ou=Groups/cn=group3) due to unsuccessful action")
        expect(logger).to receive(:warn)
          .with("Entitlements::Auditor::GitRepo: Skip sync change (update dc=net/dc=kittens/ou=Groups/cn=group4) due to unsuccessful action")
        expect(logger).to receive(:warn)
          .with("Entitlements::Auditor::GitRepo: Sync change (create dc=net/dc=kittens/ou=Groups/cn=group5) required")
        expect(logger).to receive(:warn)
          .with("Entitlements::Auditor::GitRepo: Skip sync change (create dc=net/dc=kittens/ou=Groups/cn=group6) due to unsuccessful action")
        expect(logger).to receive(:debug)
          .with("Entitlements::Auditor::GitRepo: Valid change (delete dc=net/dc=kittens/ou=Groups/cn=group1) queued")
        expect(logger).to receive(:debug)
          .with("Entitlements::Auditor::GitRepo: Valid change (delete dc=net/dc=kittens/ou=Groups/cn=group2) queued")
        expect(logger).to receive(:debug)
          .with("Entitlements::Auditor::GitRepo: Valid change (delete dc=net/dc=kittens/ou=Groups/cn=group5) queued")

        subject.send(:update_files,
          action_hash:,
          successful_actions:,
          sync_changes:,
          valid_changes:
        )

        expect(sync_changes).to eq(
          "dc=net/dc=kittens/ou=Groups/cn=group2" => "uid=russian-blue,dc=kittens,dc=net\nmetadata_cat_color=grey\nmetadata_team_id=2\nmetadata_team_name=group2\n",
          "dc=net/dc=kittens/ou=Groups/cn=group5" => "uid=snowshoe,dc=kittens,dc=net\n"
        )
        expect(valid_changes).to eq(
          "dc=net/dc=kittens/ou=Groups/cn=group1" => :delete,
          "dc=net/dc=kittens/ou=Groups/cn=group2" => :delete,
          "dc=net/dc=kittens/ou=Groups/cn=group5" => :delete
        )
      end
    end
  end

  describe "#delete_files" do
    let(:checkout_directory) { fixture("git-repo-audit-dir") }

    let(:group1) { instance_double(Entitlements::Models::Group) }
    let(:group1_dn) { "cn=group1,ou=Groups,dc=kittens,dc=net" }
    let(:group1_members) { Set.new(["uid=russian-blue,dc=kittens,dc=net", "uid=snowshoe,dc=kittens,dc=net"]) }
    let(:group2) { instance_double(Entitlements::Models::Group) }
    let(:group2_dn) { "cn=group2,ou=Groups,dc=kittens,dc=net" }
    let(:group2_members) { Set.new(["uid=russian-blue,dc=kittens,dc=net"]) }
    let(:group3) { instance_double(Entitlements::Models::Group) }
    let(:group3_dn) { "cn=group3,ou=Groups,dc=kittens,dc=net" }
    let(:group3_members) { Set.new(["uid=snowshoe,dc=kittens,dc=net"]) }
    let(:action1) { instance_double(Entitlements::Models::Action) }
    let(:action2) { instance_double(Entitlements::Models::Action) }

    let(:calc_hash) do
      {
        group1_dn => group1,
        group3_dn => group3
      }
    end

    let(:action_hash) do
      {
        group1_dn => action1,
        group2_dn => action2
      }
    end

    let(:successful_actions) { Set.new([group1_dn, group2_dn]) }

    it "returns proper hash of valid changes, sync changes" do
      allow(Entitlements::Data::Groups::Calculated).to receive(:to_h).and_return(calc_hash)
      allow(action1).to receive(:change_type).and_return(:update)
      allow(action2).to receive(:change_type).and_return(:delete)

      sync_changes = {}
      valid_changes = {}

      expect(logger).to receive(:warn)
        .with("Entitlements::Auditor::GitRepo: Sync change (delete dc=net/dc=kittens/ou=Groups/cn=group4) required")
      expect(logger).to receive(:warn)
        .with("Entitlements::Auditor::GitRepo: Sync change (delete dc=net/dc=kittens/ou=extra/cn=extragroup) required")

      subject.send(:delete_files,
        action_hash:,
        successful_actions:,
        sync_changes:,
        valid_changes:
      )

      expect(sync_changes).to eq(
        "dc=net/dc=kittens/ou=Groups/cn=group4" => :delete,
        "dc=net/dc=kittens/ou=extra/cn=extragroup" => :delete
      )
      expect(valid_changes).to eq({})
    end
  end

  describe "#member_strings_as_text" do
    let(:group) { instance_double(Entitlements::Models::Group) }

    it "returns a static string if there are no members" do
      allow(group).to receive(:member_strings).and_return(Set.new)
      expect(subject.send(:member_strings_as_text, group)).to eq("# No members\n")
    end

    it "returns the sorted member strings with newlines" do
      allow(group).to receive(:member_strings).and_return(Set.new(["alice", "bob"]))
      expect(subject.send(:member_strings_as_text, group)).to eq("alice\nbob\n")
    end

    context "with a person DN format provided" do
      let(:config) { base_config.merge("person_dn_format" => "uid=%KEY%,ou=People,dc=kittens,dc=net") }

      it "returns the sorted member strings with the template applied" do
        allow(group).to receive(:member_strings).and_return(Set.new(["alice", "bob"]))
        expect(subject.send(:member_strings_as_text, group)).to eq("uid=alice,ou=people,dc=kittens,dc=net\nuid=bob,ou=people,dc=kittens,dc=net\n")
      end
    end
  end

  describe "#metadata_strings_as_text" do
    let(:group) { instance_double(Entitlements::Models::Group) }

    it "returns a static string if there is no metadata" do
      allow(group).to receive(:metadata).and_raise(Entitlements::Models::Group::NoMetadata)
      expect(subject.send(:metadata_strings_as_text, group)).to eq("")
    end

    it "returns a static string if there is empty metadata" do
      allow(group).to receive(:metadata).and_return({})
      expect(subject.send(:metadata_strings_as_text, group)).to eq("")
    end

    it "returns a static string if there is metadata" do
      allow(group).to receive(:metadata).and_return({ "team_id" => 6, "team_name" => "team_name"})
      expect(subject.send(:metadata_strings_as_text, group)).to eq("metadata_team_id=6\nmetadata_team_name=team_name\n")
    end
  end

  describe "#commit_changes" do
    let(:repo) { instance_double(Entitlements::Util::GitRepo) }

    let(:change_hash) do
      {
        "foo/bar/baz" => "Hello world!\n",
        "foo/bar/goner" => :delete
      }
    end

    context "for a commit with no changes" do
      it "returns without doing anything" do
        subject.instance_variable_set("@repo", repo)
        expect(repo).not_to receive(:add)
        expect(repo).not_to receive(:commit)
        expect(repo).not_to receive(:push)
        subject.send(:commit_changes, {}, :sync, "My awesome message")
      end
    end

    context "for a sync commit" do
      it "stages and commits the changes" do
        subject.instance_variable_set("@repo", repo)
        expect(repo).to receive(:add).with(checkout_directory, "foo/bar/baz")
        expect(repo).to receive(:add).with(checkout_directory, "foo/bar/goner")
        filename1 = File.join(checkout_directory, "foo/bar/baz")
        filename2 = File.join(checkout_directory, "foo/bar/goner")
        expect(File).to receive(:exist?).with(filename2).and_return(true)
        fake_file = double
        expect(fake_file).to receive(:write).with("Hello world!\n")
        expect(File).to receive(:open).with(filename1, "w").and_yield(fake_file)
        expect(FileUtils).to receive(:mkdir_p).with(File.join(checkout_directory, "foo", "bar"))
        expect(FileUtils).to receive(:rm_f).with(filename2)
        expect(repo).to receive(:commit).with(checkout_directory, "[sync commit] My awesome message")
        expect(repo).to receive(:push).with(checkout_directory)
        subject.send(:commit_changes, change_hash, :sync, "My awesome message")
      end
    end

    context "for a valid commit" do
      it "stages and commits the changes" do
        subject.instance_variable_set("@repo", repo)
        expect(repo).to receive(:add).with(checkout_directory, "foo/bar/baz")
        expect(repo).to receive(:add).with(checkout_directory, "foo/bar/goner")
        filename1 = File.join(checkout_directory, "foo/bar/baz")
        filename2 = File.join(checkout_directory, "foo/bar/goner")
        expect(File).to receive(:exist?).with(filename2).and_return(true)
        fake_file = double
        expect(fake_file).to receive(:write).with("Hello world!\n")
        expect(File).to receive(:open).with(filename1, "w").and_yield(fake_file)
        expect(FileUtils).to receive(:mkdir_p).with(File.join(checkout_directory, "foo", "bar"))
        expect(FileUtils).to receive(:rm_f).with(filename2)
        expect(repo).to receive(:commit).with(checkout_directory, "My awesome message").and_return(true)
        expect(repo).to receive(:push).with(checkout_directory)
        subject.send(:commit_changes, change_hash, :valid, "My awesome message")
      end
    end

    context "for empty commits" do
      it "ignores a change if the file to be removed is already removed" do
        change_hash = { "foo/bar/goner" => :delete }
        subject.instance_variable_set("@repo", repo)
        filename2 = File.join(checkout_directory, "foo/bar/goner")
        expect(File).to receive(:exist?).with(filename2).and_return(false)
        subject.send(:commit_changes, change_hash, :valid, "My awesome message")
      end
    end
  end
end
