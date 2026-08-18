# Copyright 2026, Pulumi Corporation.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# frozen_string_literal: true

require_relative "lib/pulumi/version"

Gem::Specification.new do |spec|
  spec.name     = "pulumi"
  spec.version  = Pulumi::VERSION
  spec.authors  = ["Pulumi Corporation"]
  spec.email    = ["support@pulumi.com"]
  spec.summary  = "The Pulumi SDK for Ruby"
  spec.description = <<~DESC
    Pulumi's infrastructure as code SDK for Ruby. Define cloud infrastructure using
    real Ruby -- classes, methods, modules and blocks -- and deploy it with the
    Pulumi CLI.
  DESC
  spec.homepage = "https://www.pulumi.com"
  spec.license  = "Apache-2.0"

  # The `grpc` gem publishes precompiled binaries for CRuby >= 3.2 only, and has no
  # JRuby build at all. 3.2 reached EOL in April 2026, so 3.3 is the floor.
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["homepage_uri"]          = spec.homepage
  spec.metadata["source_code_uri"]       = "https://github.com/pulumi-labs/pulumi-ruby"
  spec.metadata["bug_tracker_uri"]       = "https://github.com/pulumi-labs/pulumi-ruby/issues"
  spec.metadata["documentation_uri"]     = "https://www.pulumi.com/docs/languages-sdks/ruby/"
  spec.metadata["changelog_uri"]         = "https://github.com/pulumi-labs/pulumi-ruby/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # The project README lives at the repo root, outside the gem, so it is reached through
  # the metadata URIs above rather than shipped here.
  spec.files = Dir[
    "lib/**/*.rb",
    "sig/**/*.rbs",
    "exe/*",
    "LICENSE"
  ]
  spec.bindir      = "exe"
  spec.executables = ["pulumi-language-ruby-exec"]
  spec.require_paths = ["lib"]

  spec.add_dependency "concurrent-ruby", "~> 1.3"
  spec.add_dependency "google-protobuf", ">= 3.25", "< 5.0"
  spec.add_dependency "grpc", "~> 1.65"
end
