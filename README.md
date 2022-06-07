# entitlements-gitrepo-auditor-plugin

[![acceptance](https://github.com/github/entitlements-gitrepo-auditor-plugin/actions/workflows/acceptance.yml/badge.svg)](https://github.com/github/entitlements-gitrepo-auditor-plugin/actions/workflows/acceptance.yml) [![test](https://github.com/github/entitlements-gitrepo-auditor-plugin/actions/workflows/test.yml/badge.svg)](https://github.com/github/entitlements-gitrepo-auditor-plugin/actions/workflows/test.yml) [![lint](https://github.com/github/entitlements-gitrepo-auditor-plugin/actions/workflows/lint.yml/badge.svg)](https://github.com/github/entitlements-gitrepo-auditor-plugin/actions/workflows/lint.yml) [![coverage](https://img.shields.io/badge/coverage-100%25-success)](https://img.shields.io/badge/coverage-100%25-success) [![style](https://img.shields.io/badge/code%20style-rubocop--github-blue)](https://github.com/github/rubocop-github)

`entitlements-gitrepo-auditor-plugin` is an [entitlements-app](https://github.com/github/entitlements-app) plugin allowing further auditing capabilities in entitlements by writing each deploy log to a separate GitHub repo.

## Usage

Your `entitlements-app` config `config/entitlements.yaml` runs through ERB interpretation automatically. You can extend your entitlements configuration to load plugins like so:

```ruby
<%-
  unless ENV['CI_MODE']
    begin
      require_relative "/data/entitlements/lib/entitlements-and-plugins"
    rescue Exception
      begin
        require_relative "lib/entitlements-and-plugins"
      rescue Exception
        # We might not have the plugins installed and still want this file to be
        # loaded. Don't raise anything but silently fail.
      end
    end
  end
-%>
```

You can then define `lib/entitlements-and-plugins` like so:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

ENV["BUNDLE_GEMFILE"] = File.expand_path("../../Gemfile", File.dirname(__FILE__))
require "bundler/setup"
require "entitlements"

# require entitlements plugins here
require "entitlements/auditor/gitrepo"
require "entitlements/util/gitrepo"
```

Any plugins defined in `lib/entitlements-and-plugins` will be loaded and used at `entitlements-app` runtime.

## Features

### Git Repo Auditing

You can add automatic auditing to a separate GitRepo by enabling the following `entitlements.yaml` config:

```ruby
<%-
    # NOTE: GITREPO_SSH_KEY must be base64 encoded.
    sshkey = ENV.fetch("GITREPO_SSH_KEY")
    shipper = ENV.fetch("GIT_SHIPPER", "<unknown person>")
    what = ["entitlements", ENV.fetch("GIT_BRANCH", "<unknown branch>")].join("/")
    sha = ENV.fetch("GIT_SHA1", "<unknown sha>")
    url = "https://github.com/github/entitlements-config/commit/#{sha}"
    commit_message = "#{shipper} deployed #{what} (#{url})"
-%>
auditors:
  - auditor_class: GitRepo
    checkout_directory: <%= ENV["GITREPO_CHECKOUT_DIRECTORY"] %>
    commit_message: <%= commit_message %>
    git_name: GitRepoUser
    git_email: gitrepousers@users.noreply
    person_dn_format: uid=%KEY%,ou=People,dc=github,dc=net
    repo: github/entitlements-config-auditlog
    sshkey: '<%= sshkey %>'
<%- end -%>
```

At the end of each `entitlements-app` run, the `entitlements-gitrepo-auditor-plugin` will write a commit to the repo defined above with the details of the deployment.
