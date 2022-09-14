# frozen_string_literal: true
require_relative "../../spec_helper"
require "tmpdir"

describe Entitlements::Util::GitRepo do

  let(:directory) { "/tmp/asdlkfjafdiejwroiwejfalskdfjdsklf" }
  let(:logger) { instance_double(Logger) }
  let(:subject) { described_class.new(repo: "kittens/fluffy", sshkey: "xyz123", logger: logger) }

  describe "#add" do
    it "executes the command" do
      allow(subject).to receive(:validate_git_repository!)
      expect(subject).to receive(:git).with(directory, ["add", "foo/bar/baz.txt"])
      expect(subject.add(directory, "foo/bar/baz.txt")).to be nil
    end
  end

  describe "#clone" do
    it "raises if the directory already exists" do
      allow(File).to receive(:exist?).with(directory).and_return(true)
      expect do
        subject.clone(directory)
      end.to raise_error(Errno::EEXIST, "File exists - Cannot clone to #{directory}: already exists")
    end

    it "executes the commands" do
      allow(File).to receive(:exist?).with(directory).and_return(false)
      expect(logger).to receive(:debug).with("Cloning from GitHub to #{directory}")
      expect(FileUtils).to receive(:mkdir_p).with(directory)
      expect(subject).to receive(:git).with(directory, ["clone", "git@github.com:kittens/fluffy.git", "."], ssh: true)
      expect(subject.clone(directory)).to be nil
    end
  end

  describe "#commit" do
    it "executes the command" do
      allow(subject).to receive(:validate_git_repository!)
      expect(subject).to receive(:git).with(directory, ["commit", "-m", "My commit message"])
      expect(subject.commit(directory, "My commit message")).to be nil
    end

    it "skips the commit if it receives a command error" do
      allow(subject).to receive(:validate_git_repository!)
      expect(subject).to receive(:git).with(directory, ["commit", "-m", "My commit message"]).and_raise(Entitlements::Util::GitRepo::CommandError)
      expect(logger).to receive(:info).with("No changes to git repository")
      expect(subject.commit(directory, "My commit message")).to be nil
    end
  end

  describe "#configure" do
    it "executes the commands and logs messages" do
      allow(subject).to receive(:validate_git_repository!)
      expect(logger).to receive(:debug).with("Configuring #{directory} with name=\"Hubot\" email=\"hubot@github.com\"")
      expect(subject).to receive(:git).with(directory, ["config", "user.name", "Hubot"])
      expect(subject).to receive(:git).with(directory, ["config", "user.email", "hubot@github.com"])
      expect(subject.configure(directory, "Hubot", "hubot@github.com")).to be nil
    end
  end

  describe "#pull" do
    let(:error_message) do
      "No such file or directory - Cannot pull in #{directory}: does not exist or is not a git repo"
    end

    it "raises if the directory does not exist" do
      allow(File).to receive(:directory?).with(directory).and_return(false)
      expect do
        subject.pull(directory)
      end.to raise_error(Errno::ENOENT, error_message)
    end

    it "raises if {directory}/.git does not exist" do
      allow(File).to receive(:directory?).with(directory).and_return(true)
      allow(File).to receive(:directory?).with(File.join(directory, ".git")).and_return(false)
      expect do
        subject.pull(directory)
      end.to raise_error(Errno::ENOENT, error_message)
    end

    it "executes the commands" do
      allow(File).to receive(:directory?).with(directory).and_return(true)
      allow(File).to receive(:directory?).with(File.join(directory, ".git")).and_return(true)
      expect(logger).to receive(:debug).with("Pulling from GitHub to #{directory}")
      expect(subject).to receive(:git).with(directory, ["reset", "--hard", "HEAD"])
      expect(subject).to receive(:git).with(directory, ["clean", "-f", "-d"])
      expect(subject).to receive(:git).with(directory, ["pull"], ssh: true)
      expect(subject.pull(directory)).to be nil
    end
  end

  describe "#push" do
    it "executes the commands" do
      allow(subject).to receive(:validate_git_repository!)
      expect(logger).to receive(:debug).with("Pushing to GitHub from #{directory}")
      expect(subject).to receive(:git).with(directory, ["push", "origin", "master"], ssh: true)
      expect(subject.push(directory)).to be nil
    end
  end

  describe "#git" do
    it "raises if given a non-existing directory" do
      error_message = "No such file or directory - Attempted to run 'git' in non-existing directory #{directory}!"
      allow(File).to receive(:directory?).with(directory).and_return(false)
      expect { subject.send(:git, directory, ["pet the", "kittens"]) }.to raise_error(Errno::ENOENT, error_message)
    end

    it "raises on an error when :raise_on_error is not defined" do
      allow(File).to receive(:directory?).with(directory).and_return(true)
      exitstatus = instance_double(Process::Status)
      allow(exitstatus).to receive(:exitstatus).and_return(1)
      expect(subject).to receive(:open3_git_execute)
        .with("/tmp/asdlkfjafdiejwroiwejfalskdfjdsklf", "git pet\\ the kittens", false)
        .and_return(["The command failed\n   very, very badly", "Everything is terrible", exitstatus])
      expect(logger).to receive(:warn).with("[stdout] The command failed")
      expect(logger).to receive(:warn).with("[stdout]    very, very badly")
      expect(logger).to receive(:warn).with("[stderr] Everything is terrible")
      expect(logger).to receive(:fatal).with("Command failed (1): git pet\\ the kittens")
      expect { subject.send(:git, directory, ["pet the", "kittens"]) }.to raise_error(Entitlements::Util::GitRepo::CommandError)
    end

    it "does not raise on an error when :raise_on_error is false" do
      allow(File).to receive(:directory?).with(directory).and_return(true)
      exitstatus = instance_double(Process::Status)
      allow(exitstatus).to receive(:exitstatus).and_return(1)
      expect(subject).to receive(:open3_git_execute)
        .with("/tmp/asdlkfjafdiejwroiwejfalskdfjdsklf", "git pet\\ the kittens", false)
        .and_return(["The command failed\n   very, very badly", "Everything is terrible", exitstatus])
      result = subject.send(:git, directory, ["pet the", "kittens"], raise_on_error: false)
      expect(result).to eq(
        stdout: "The command failed\n   very, very badly",
        stderr: "Everything is terrible",
        status: 1
      )
    end

    it "returns the output, error, and exit code from open3" do
      allow(File).to receive(:directory?).with(directory).and_return(true)
      exitstatus = instance_double(Process::Status)
      allow(exitstatus).to receive(:exitstatus).and_return(0)
      expect(subject).to receive(:open3_git_execute)
        .with("/tmp/asdlkfjafdiejwroiwejfalskdfjdsklf", "git pet\\ the kittens", false)
        .and_return(["The command succeeded\n   and the kittens are fluffy", "", exitstatus])
      result = subject.send(:git, directory, ["pet the", "kittens"])
      expect(result).to eq(
        stdout: "The command succeeded\n   and the kittens are fluffy",
        stderr: "",
        status: 0
      )
    end
  end

  describe "#open3_git_execute" do
    it "returns stdout, stderr, code when invoked without SSH option" do
      exitstatus = instance_double(Process::Status)
      allow(exitstatus).to receive(:exitstatus).and_return(0)

      expect(Open3).to receive(:capture3).with("git pet kittens", chdir: directory)
        .and_return(["Your output here", "", exitstatus])
      expect(logger).to receive(:debug).with("Execute: git pet kittens")

      result = subject.send(:open3_git_execute, directory, "git pet kittens")
      expect(result).to eq(["Your output here", "", exitstatus])
    end

    it "creates a custom SSH program, stores the key, sets the environment, and executes" do
      exitstatus = instance_double(Process::Status)
      allow(exitstatus).to receive(:exitstatus).and_return(0)

      begin
        tempdir = Dir.mktmpdir
        allow(Dir).to receive(:mktmpdir).and_return(tempdir)

        expect(Open3).to receive(:capture3).with({"GIT_SSH"=>"#{tempdir}/ssh"}, "git pet kittens", chdir: directory)
          .and_return(["Your output here", "", exitstatus])
        expect(logger).to receive(:debug).with("Execute: git pet kittens")

        expect(FileUtils).to receive(:remove_entry_secure).with(tempdir)

        result = subject.send(:open3_git_execute, directory, "git pet kittens", true)
        expect(result).to eq(["Your output here", "", exitstatus])

        # Because we stubbed away the cleanup we can test here
        expect(File.directory?(tempdir)).to eq(true)

        sshkey = File.join(tempdir, "key")
        expect(File.file?(sshkey)).to eq(true)
        expect(sprintf("%o", File.stat(sshkey).mode)).to eq("100400")
        expect(File.read(sshkey)).to eq("xyz123")

        ssh = File.join(tempdir, "ssh")
        expect(File.file?(ssh)).to eq(true)
        expect(sprintf("%o", File.stat(ssh).mode)).to eq("100700")
        expect(File.read(ssh)).to start_with("#!/bin/sh")
      ensure
        expect(FileUtils).to receive(:remove_entry_secure).and_call_original
        FileUtils.remove_entry_secure(tempdir) if File.directory?(tempdir)
      end

      # Make sure we cleaned up
      expect(File.directory?(tempdir)).to eq(false)
    end
  end
end
