# frozen_string_literal: true

# NOTE: This currently does NOT use "rugged" because we want to use SSH to connect to GitHub,
# but cannot be assured that "rugged" is compiled with SSH support everywhere this might run.
# Hence, "open3" is used to access an assumed "git" binary.

require "fileutils"
require "open3"
require "shellwords"
require "tmpdir"

module Entitlements
  class Util
    class GitRepo
      include ::Contracts::Core
      C = ::Contracts

      class CommandError < StandardError; end

      # This is hard-coded to use GitHub, just because. However this is here to support
      # overriding this if needed (e.g. acceptance tests).
      attr_accessor :github

      # Constructor.
      #
      # repo   - Name of the repo on GitHub (e.g. github/entitlements-audit)
      # sshkey - Private SSH key for a user with push access to the repo
      # logger - Logger object
      #
      # Returns nothing.
      Contract C::KeywordArgs[
        repo: String,
        sshkey: String,
        logger: C::Maybe[C::Or[Logger, Entitlements::Auditor::Base::CustomLogger]]
      ] => C::Any
      def initialize(repo:, sshkey:, logger: Entitlements.logger)
        @logger = logger
        @repo = repo
        @sshkey = sshkey
        @github = "git@github.com:"
      end

      # Run "git add" on a file.
      #
      # dir      - A String with the path where this is to take place.
      # filename - File name, relative to dir, to be added.
      #
      # Returns nothing.
      Contract String, String => nil
      def add(dir, filename)
        validate_git_repository!(dir)
        git(dir, ["add", filename])
        nil
      end

      # Clone git repo into the specified directory.
      #
      # dir - A String with the path where this is to take place.
      #
      # Returns nothing.
      Contract String => nil
      def clone(dir)
        if File.exist?(dir)
          raise Errno::EEXIST, "Cannot clone to #{dir}: already exists"
        end

        logger.debug "Cloning from GitHub to #{dir}"
        FileUtils.mkdir_p(dir)
        git(dir, ["clone", repo_url, "."], ssh: true)
        nil
      end

      # Commit to the repo.
      #
      # dir            - A String with the path where this is to take place.
      # commit_message - A String with the commit message.
      #
      # Returns nothing.
      Contract String, String => nil
      def commit(dir, commit_message)
        validate_git_repository!(dir)
        git(dir, ["commit", "-m", commit_message])
        nil
      end

      # Configure the name and e-mail address in the repo, so git commit knows what to use.
      #
      # dir   - A String with the path where this is to take place.
      # name  - A String to pass to user.name
      # email - A String to pass to user.email
      #
      # Returns nothing.
      Contract String, String, String => nil
      def configure(dir, name, email)
        validate_git_repository!(dir)
        logger.debug "Configuring #{dir} with name=#{name.inspect} email=#{email.inspect}"
        git(dir, ["config", "user.name", name])
        git(dir, ["config", "user.email", email])
        nil
      end

      # Pull the latest from GitHub.
      #
      # dir - A String with the path where this is to take place.
      #
      # Returns nothing.
      Contract String => nil
      def pull(dir)
        validate_git_repository!(dir)
        logger.debug "Pulling from GitHub to #{dir}"
        git(dir, ["reset", "--hard", "HEAD"])
        git(dir, ["clean", "-f", "-d"])
        git(dir, ["pull"], ssh: true)
        nil
      end

      # Push the branch to GitHub.
      #
      # dir - A String with the path where this is to take place.
      #
      # Returns nothing.
      Contract String => nil
      def push(dir)
        validate_git_repository!(dir)
        logger.debug "Pushing to GitHub from #{dir}"
        git(dir, ["push", "origin", "master"], ssh: true)
        nil
      end

      private

      attr_reader :repo, :sshkey, :logger

      # Helper method to refer to the repository on GitHub.
      #
      # Takes no arguments.
      #
      # Returns a String with the URL on GitHub.
      Contract C::None => String
      def repo_url
        "#{github}#{repo}.git"
      end

      # Helper to validate that a particular directory contains a git repository.
      #
      # dir - Directory where the command should be run.
      #
      # Returns nothing (but may raise Errno::ENOENT).
      Contract String => nil
      def validate_git_repository!(dir)
        return if File.directory?(dir) && File.directory?(File.join(dir, ".git"))
        raise Errno::ENOENT, "Cannot pull in #{dir}: does not exist or is not a git repo"
      end

      # Run a git command.
      #
      # dir     - Directory where the command should be run.
      # args    - An Array of Strings with the command line arguments.
      # options - Additional options?
      #
      # Returns a hash of { stdout: String, stderr: String, status: Integer }
      Contract String, C::ArrayOf[String], C::Maybe[C::HashOf[Symbol => C::Any]] => C::HashOf[Symbol => C::Any]
      def git(dir, args, options = {})
        unless File.directory?(dir)
          raise Errno::ENOENT, "Attempted to run 'git' in non-existing directory #{dir}!"
        end

        commandline = ["git", args].flatten.map { |str| Shellwords.escape(str) }.join(" ")

        out, err, code = open3_git_execute(dir, commandline, options.fetch(:ssh, false))
        if code.exitstatus != 0 && options.fetch(:raise_on_error, true)
          if out && !out.empty?
            out.split("\n").reject { |str| str.strip.empty? }.each { |str| logger.warn "[stdout] #{str}" }
          end
          if err && !err.empty?
            err.split("\n").reject { |str| str.strip.empty? }.each { |str| logger.warn "[stderr] #{str}" }
          end
          logger.fatal "Command failed (#{code.exitstatus}): #{commandline}"
          raise CommandError, "git command failed"
        end

        { stdout: out, stderr: err, status: code.exitstatus }
      end

      # Actually execute a command using open3. This handles wrapping the SSH key and git.
      #
      # dir         - Directory where to run the command
      # commandline - Commands to execute (must be properly escapted)
      # ssh         - True to set up a temporary directory and do the SSH key, false to skip this.
      #
      # Returns STDOUT, STDERR, EXITSTATUS
      Contract String, String, C::Maybe[C::Bool] => [String, String, Process::Status]
      def open3_git_execute(dir, commandline, ssh = false)
        logger.debug "Execute: #{commandline}"

        unless ssh
          return Open3.capture3(commandline, chdir: dir)
        end

        begin
          # Replace GIT_SSH with our custom SSH wrapper that installs the key and disables anything
          # else custom that might be going on in the environment. Turn off prompts for the SSH key for
          # github.com being trusted or not, only use the provided key as the identity, and ignore any
          # ~/.ssh/config file the user running this might have set up.
          tempdir = Dir.mktmpdir
          File.open(File.join(tempdir, "key"), "w") { |f| f.write(sshkey) }
          File.open(File.join(tempdir, "ssh"), "w") do |f|
            f.puts "#!/bin/sh"
            f.puts "exec /usr/bin/ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \\"
            f.puts "  -o IdentityFile=#{Shellwords.escape(File.join(tempdir, 'key'))} -o IdentitiesOnly=yes \\"
            f.puts "  -F /dev/null \\"
            f.puts "  \"$@\""
          end
          FileUtils.chmod(0400, File.join(tempdir, "key"))
          FileUtils.chmod(0700, File.join(tempdir, "ssh"))

          # Run the command in the directory `dir` with GIT_SSH pointed at the wrapper script built above.
          # Returns STDOUT, STDERR, EXITSTATUS.
          Open3.capture3({ "GIT_SSH" => File.join(tempdir, "ssh") }, commandline, chdir: dir)
        ensure
          # Always kill the temporary directory after running, no matter what happened.
          FileUtils.remove_entry_secure(tempdir)
        end
      end
    end
  end
end
