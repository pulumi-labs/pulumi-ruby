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

# Emits the gems visible to the current program as JSON on stdout.
#
# This reports *every* gem, including the core `pulumi` SDK, and leaves it to the Go
# language host to decide which of them are Pulumi packages that need a plugin. Those are
# two different questions -- GetProgramDependencies wants the whole dependency list, while
# GetRequiredPackages wants only the ones backed by a provider -- and answering both from
# one filtered list is what made the core SDK go missing from the dependency report.
#
# Resolving gem locations is RubyGems' job, not ours: reimplementing its search path in Go
# would drift the moment Bundler, a vendored bundle path, or a path: dependency got
# involved. So we ask Ruby and parse the answer.
#
# Usage: ruby list_packages.rb [--direct-only]

require "json"

direct_only = ARGV.include?("--direct-only")

# Under `bundle exec`, RubyGems' activation is already narrowed to the bundle, so
# Gem::Specification reflects exactly the resolved set. Outside a bundle it reflects
# everything installed, which is the best available answer when a program has no Gemfile.
specs = Gem::Specification.to_a

# Default gems ship with Ruby itself -- json, set, and so on. They are part of the
# language, not of the program's dependencies, and reporting them would bury the few that
# matter.
specs = specs.reject { |spec| spec.respond_to?(:default_gem?) && spec.default_gem? }

# Without Bundler the same gem can appear at several versions; the newest one is what
# `require` would pick, so report that.
specs = specs.group_by(&:name).map { |_, versions| versions.max_by(&:version) }

if direct_only
  direct =
    begin
      require "bundler"
      Bundler.definition.dependencies.map(&:name)
    rescue StandardError
      nil
    end
  specs = specs.select { |spec| direct.include?(spec.name) } unless direct.nil?
end

packages = specs.map do |spec|
  entry = {
    "name" => spec.name,
    "version" => spec.version.to_s,
    "gemDir" => spec.gem_dir
  }

  # Passed through verbatim for Go to unmarshal, so the schema has one definition rather
  # than two that can disagree.
  plugin_json_path = File.join(spec.gem_dir, "pulumi-plugin.json")
  entry["pluginJSON"] = File.read(plugin_json_path) if File.file?(plugin_json_path)

  entry
end

puts JSON.generate(packages)
