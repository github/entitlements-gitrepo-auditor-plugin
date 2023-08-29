# frozen_string_literal: true

# This audit provider dumps a sorted list of member DNs and group metadata to a file in a directory structure,
# and when the entitlements run is finished, commits the changes to the git repo.
require "base64"

module Entitlements
  class Auditor
    class GitRepo < Entitlements::Auditor::Base
      include ::Contracts::Core
      C = ::Contracts

      # Setup method for git repo: this will clone the repo into the configured directory if
      # it does not exist, or pull the latest changes from the configured directory if it does.
      # We can also validate that the required parameters are supplied here.
      #
      # Takes no arguments.
      #
      # Returns nothing.
      Contract C::None => C::Any
      def setup
        validate_options!
        operation = File.directory?(checkout_directory) ? :pull : :clone

        logger.debug "Preparing #{checkout_directory}"
        @repo = Entitlements::Util::GitRepo.new(
          repo: config["repo"],
          sshkey: Base64.decode64(config["sshkey"]),
          logger:
        )
        @repo.github = config["github_override"] if config["github_override"]
        @repo.send(operation, checkout_directory)
        @repo.configure(checkout_directory, config["git_name"], config["git_email"])
        logger.debug "Directory #{checkout_directory} prepared"
      end

      # Commit method for git repo: this will write out all of the entitlements files to the
      # configured directory, then do a git commit, and then push to GitHub.
      #
      # actions            - Array of Entitlements::Models::Action (all requested actions)
      # successful_actions - Set of DNs (successfully applied actions)
      # provider_exception - Exception raised by a provider when applying (hopefully nil)
      #
      # Returns nothing.
      Contract C::KeywordArgs[
        actions: C::ArrayOf[Entitlements::Models::Action],
        successful_actions: C::SetOf[String],
        provider_exception: C::Or[nil, Exception]
      ] => C::Any
      def commit(actions:, successful_actions:, provider_exception:)
        raise "Must run setup method before running commit method" unless @repo

        sync_changes = {}
        valid_changes = {}

        commitable_actions = actions_with_membership_change(actions)
        action_hash = commitable_actions.map { |action| [action.dn, action] }.to_h

        %w[update_files delete_files].each do |m|
          send(
            m.to_sym,
            action_hash:,
            successful_actions:,
            sync_changes:,
            valid_changes:
          )
        end

        # If there is anything out-of-sync and the provider did not throw an exception, create
        # a special sync commit to update things.
        if sync_changes.any?
          if provider_exception
            logger.warn "Not committing #{sync_changes.size} unrecognized change(s) due to provider exception"
          else
            logger.warn "Sync changes required: count=#{sync_changes.size}"
            commit_changes(sync_changes, :sync, commit_message)
          end
        end

        # If there are any valid changes, create a commit to update things.
        if valid_changes.any?
          logger.debug "Committing #{valid_changes.size} change(s) to git repository"
          commit_changes(valid_changes, :valid, commit_message)
        elsif sync_changes.empty?
          logger.debug "No changes to git repository"
        end
      end

      private

      # The checkout directory from the configuration. Separated out here as a method so
      # it can be more easily stubbed from tests.
      #
      # Takes no arguments.
      #
      # Returns a String with the checkout directory.
      Contract C::None => String
      def checkout_directory
        config["checkout_directory"]
      end

      # Commit message - read from the provider's configuration. (This is so the commit
      # message can be passed in as an ERB for flexibility.)
      #
      # Takes no arguments.
      #
      # Returns a String with the commit message.
      Contract C::None => String
      def commit_message
        config.fetch("commit_message")
      end

      # Check the current calculation object for any added or updated groups. Break changes
      # apart into sync changes and valid changes.
      #
      # action_hash        - The hash of actions
      # successful_actions - Set of DNs that were successfully updated/added/deleted
      # sync_changes       - The hash (will be updated)
      # valid_changes      - The hash (will be updated)
      #
      # Returns nothing.
      Contract C::KeywordArgs[
        action_hash: C::HashOf[String => Entitlements::Models::Action],
        successful_actions: C::SetOf[String],
        sync_changes: C::HashOf[String => C::Or[String, :delete]],
        valid_changes: C::HashOf[String => C::Or[String, :delete]]
      ] => C::Any
      def update_files(action_hash:, successful_actions:, sync_changes:, valid_changes:)
        # Need to add nil entries onto the calculated hash for action == delete. These entries
        # simply disappear from the calculated hash, but we need to iterate over them too.
        iterable_hash = Entitlements::Data::Groups::Calculated.to_h.dup
        action_hash.select { |dn, action| action.change_type == :delete }.each do |dn, _action|
          iterable_hash[dn] = nil
        end

        iterable_hash.each do |dn, group|
          filename = path_from_dn(dn)
          target_file = File.join(checkout_directory, filename)
          action = action_hash[dn]

          if action.nil?
            handle_no_action(sync_changes, valid_changes, filename, target_file, group)
          elsif action.change_type == :delete
            handle_delete(sync_changes, valid_changes, action, successful_actions, filename, target_file, dn)
          elsif action.change_type == :add
            handle_add(sync_changes, valid_changes, action, successful_actions, filename, target_file, dn, group)
          elsif action.change_type == :update
            handle_update(sync_changes, valid_changes, action, successful_actions, filename, target_file, dn, group)
          else
            # :nocov:
            raise "Unhandled condition for action #{action.inspect}"
            # :nocov:
          end
        end
      end

      # Find files that need to be deleted. All files deleted because of actions are handled in the
      # 'updated_files' method. This method is truly meant for cleanup only.
      #
      # action_hash        - The hash of actions
      # successful_actions - Set of DNs that were successfully updated/added/deleted
      # sync_changes       - The hash (will be updated)
      # valid_changes      - The hash (will be updated)
      #
      # Returns nothing.
      Contract C::KeywordArgs[
        action_hash: C::HashOf[String => Entitlements::Models::Action],
        successful_actions: C::SetOf[String],
        sync_changes: C::HashOf[String => C::Or[String, :delete]],
        valid_changes: C::HashOf[String => C::Or[String, :delete]]
      ] => C::Any
      def delete_files(action_hash:, successful_actions:, sync_changes:, valid_changes:)
        Dir.chdir checkout_directory
        Dir.glob("**/*") do |child|
          child_file = File.join(checkout_directory, child)
          next unless File.file?(child_file)
          next if File.basename(child) == "README.md"

          # !! NOTE !!
          # Defined actions (:add, :update, :delete) are handled in update_files. This
          # logic only deals with files that exist and shouldn't and don't have action being
          # taken upon them.

          child_dn = dn_from_path(child)
          if Entitlements::Data::Groups::Calculated.to_h.key?(child_dn)
            # File is supposed to exist and it exists. Do nothing.
          elsif action_hash[child_dn].nil?
            # File is not supposed to exist, but it does, and there was no action concerning it.
            # Set up sync change to delete file.
            logger.warn "Sync change (delete #{child}) required"
            sync_changes[child] = :delete
          end
        end
      end

      # For readability: Handle no-action logic.
      def handle_no_action(sync_changes, valid_changes, filename, target_file, group)
        group_expected_contents = group_contents_as_text(group)

        if File.file?(target_file)
          file_contents = File.read(target_file)
          unless file_contents == group_expected_contents
            logger.warn "Sync change (update #{filename}) required"
            sync_changes[filename] = group_expected_contents
          end
        elsif group.member_strings.empty?
          # The group does not currently exist in the file system nor is it created in the
          # provider because it has no members. We can skip over this case.
        else
          logger.warn "Sync change (create #{filename}) required"
          sync_changes[filename] = group_expected_contents
        end
      end

      # For readability: Handle 'delete' logic.
      def handle_delete(sync_changes, valid_changes, action, successful_actions, filename, target_file, dn)
        group_expected_contents = group_contents_as_text(action.existing)

        if File.file?(target_file)
          file_contents = File.read(target_file)
          if successful_actions.member?(dn)
            if file_contents == group_expected_contents
              # Good: The file had the correct prior content so it can just be deleted.
              logger.debug "Valid change (delete #{filename}) queued"
              valid_changes[filename] = :delete
            else
              # Bad: The file had incorrect prior content. Sync to the previous members and then delete it.
              logger.warn "Sync change (update #{filename}) required"
              sync_changes[filename] = group_expected_contents
              logger.debug "Valid change (delete #{filename}) queued"
              valid_changes[filename] = :delete
            end
          elsif file_contents == group_expected_contents
            # Good: The file already had the correct prior content. Since the action was unsuccessful
            # just skip this case doing nothing.
            logger.warn "Skip change (delete #{filename}) due to unsuccessful action"
          else
            # Bad: The file had incorrect prior content. Wait for the successful run to sync the change.
            logger.warn "Skip sync change (update #{filename}) due to unsuccessful action"
          end
        else
          if successful_actions.member?(dn)
            # Bad: The file didn't exist before but it should have. Create it now and then delete it.
            logger.warn "Sync change (create #{filename}) required"
            sync_changes[filename] = group_expected_contents
            logger.debug "Valid change (delete #{filename}) queued"
            valid_changes[filename] = :delete
          else
            # Bad: The file didn't exist before but it should have. Wait for the successful run to sync the change.
            logger.warn "Skip sync change (create #{filename}) due to unsuccessful action"
          end
        end
      end

      # For readability: Handle 'add' logic.
      def handle_add(sync_changes, valid_changes, action, successful_actions, filename, target_file, dn, group)
        group_expected_contents = group_contents_as_text(group)

        if File.file?(target_file)
          if successful_actions.member?(dn)
            # Weird case: The file was not supposed to be there but for some reason it is.
            # Do a sync commit to remove the file (then a valid commit to add it back).
            logger.warn "Sync change (delete #{filename}) required"
            sync_changes[filename] = :delete
          else
            # Weird case: The file was there but the action to create the group was unsuccessful.
            # Do nothing here, to let this get sync'd and updated when it completes successfully.
            logger.warn "Skip sync change (delete #{filename}) due to unsuccessful action"
          end
        end

        if successful_actions.member?(dn)
          logger.debug "Valid change (create #{filename}) queued"
          valid_changes[filename] = group_expected_contents
        else
          logger.warn "Skip change (add #{filename}) due to unsuccessful action"
        end
      end

      # For readability: Handle 'update' logic.
      def handle_update(sync_changes, valid_changes, action, successful_actions, filename, target_file, dn, group)
        group_expected_contents = group_contents_as_text(group)
        group_existing_contents = group_contents_as_text(action.existing)

        if File.file?(target_file)
          if successful_actions.member?(dn)
            if File.read(target_file) == group_existing_contents
              # Good: The file had the correct prior content so it can just be updated with the new content.
              logger.debug "Valid change (update #{filename}) queued"
              valid_changes[filename] = group_expected_contents
            else
              # Bad: The file had incorrect prior content. Sync to the previous members and then update it.
              logger.warn "Sync change (update #{filename}) required"
              sync_changes[filename] = group_existing_contents
              logger.debug "Valid change (update #{filename}) queued"
              valid_changes[filename] = group_expected_contents
            end
          elsif File.read(target_file) == group_existing_contents
            # Good: The file already had the correct prior content. Since the action was unsuccessful
            # just skip this case doing nothing.
            logger.warn "Skip change (update #{filename}) due to unsuccessful action"
          else
            # Bad: The file had incorrect prior content. Wait for the successful run to sync the change.
            logger.warn "Skip sync change (update #{filename}) due to unsuccessful action"
          end
        else
          if successful_actions.member?(dn)
            # Bad: The file didn't exist before but it should have. Create it now and then update it.
            logger.warn "Sync change (create #{filename}) required"
            sync_changes[filename] = group_existing_contents
            logger.debug "Valid change (update #{filename}) queued"
            valid_changes[filename] = group_expected_contents
          else
            # Bad: The file didn't exist before but it should have. Wait for the successful run to sync the change.
            logger.warn "Skip sync change (create #{filename}) due to unsuccessful action"
          end
        end
      end

      # This defines the file format within this repository. Just dump the list of users
      # and sort them, one per line.
      #
      # group - Entitlements::Models::Group object
      #
      # Returns a String with the members sorted and delimited by newlines.
      Contract Entitlements::Models::Group => String
      def member_strings_as_text(group)
        if group.member_strings.empty?
          return "# No members\n"
        end

        member_array = if config["person_dn_format"]
          group.member_strings.map { |ms| config["person_dn_format"].gsub("%KEY%", ms).downcase }
        else
          group.member_strings.map(&:downcase)
        end

        member_array.sort.join("\n") + "\n"
      end

      # This defines the file format within this repository. Dump the metadata from the group, and return it as one
      # metadata declaration per line ie "metadata_team_name = my_github_team"
      #
      # group - Entitlements::Models::Group object
      #
      # Returns a String with the metadata sorted and delimited by newlines.
      Contract Entitlements::Models::Group => String
      def metadata_strings_as_text(group)
        begin
          group_metadata = group.metadata
          ignored_metadata = ["_filename"]
          ignored_metadata.each do |metadata|
            group_metadata.delete(metadata)
          end

          if group_metadata.empty?
            return ""
          end

          metadata_array = group_metadata.map { |k, v| "metadata_#{k}=#{v}" }

          return metadata_array.sort.join("\n") + "\n"
        rescue Entitlements::Models::Group::NoMetadata
          return ""
        end
      end

      # This defines the file format within this repository. Grabs the full
      # contents of an entitlements group - that is the members and the metadata - and returns it
      #
      # group - Entitlements::Models::Group object
      #
      # Returns a String with the content sorted and delimited by newlines.
      Contract Entitlements::Models::Group => String
      def group_contents_as_text(group)
        group_members = member_strings_as_text(group)
        group_metadata = metadata_strings_as_text(group)
        group_members + group_metadata
      end

      # Make changes in the directory tree, then "git add" and "git commit" the changes
      # with the specified commit message.
      #
      # changes - Hash of { filename => content } (or { filename => :delete })
      # type    - Either :sync or :valid
      #
      # Returns nothing.
      Contract C::HashOf[String => C::Or[String, :delete]], C::Or[:sync, :valid], String => nil
      def commit_changes(expected_changes, type, commit_message)
        return if expected_changes.empty?

        valid_changes = false

        expected_changes.each do |filename, content|
          target = File.join(checkout_directory, filename)
          if content == :delete
            # It's possible for two separate commits to the gitrepo to remove the same file, causing a race condition
            # The first commit will delete the file from the gitrepo, and the second commit will fail with an empty commit
            # For that reason, we only track a removal as a valid change if the file exists and would actually be removed
            next unless File.exist?(target)

            FileUtils.rm_f target
          else
            FileUtils.mkdir_p File.dirname(target)
            File.open(target, "w") { |f| f.write(content) }
          end
          valid_changes = true
          @repo.add(checkout_directory, filename)
        end
        return unless valid_changes

        if type == :sync
          @repo.commit(checkout_directory, "[sync commit] #{commit_message}")
        else
          @repo.commit(checkout_directory, commit_message)
        end
        @repo.push(checkout_directory)
      end

      # Validate the options in 'config'. Raise an error if options are invalid.
      #
      # Takes no arguments.
      #
      # Returns nothing.
      # :nocov:
      Contract C::None => nil
      def validate_options!
        require_config_keys %w[checkout_directory commit_message git_name git_email repo sshkey]

        unless config["repo"] =~ %r{\A([^/]+)/([^/]+)\z}
          configuration_error "'repo' must be of the form 'organization/reponame'"
        end

        begin
          Base64.decode64(config["sshkey"])
        rescue => e
          configuration_error "'sshkey' could not be base64 decoded: #{e.class} #{e.message}"
        end

        nil
      end
      # :nocov:
    end
  end
end
