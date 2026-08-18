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

module Pulumi
  # How long the engine should wait for a resource operation before giving up.
  class CustomTimeouts
    attr_reader :create, :update, :delete

    # Durations are Go-style strings, e.g. "10m", "1h30m".
    def initialize(create: nil, update: nil, delete: nil)
      @create = create
      @update = update
      @delete = delete
    end
  end

  # Options that change how the engine manages a resource, as distinct from the inputs it
  # passes to the provider.
  #
  #   Pulumi::ResourceOptions.new(parent: self, depends_on: [db], protect: true)
  class ResourceOptions
    attr_accessor :parent, :depends_on, :protect, :provider, :providers, :version,
                  :plugin_download_url, :ignore_changes, :additional_secret_outputs,
                  :delete_before_replace, :replace_on_changes, :retain_on_delete,
                  :deleted_with, :custom_timeouts, :import, :aliases

    def initialize(parent: nil, depends_on: nil, protect: nil, provider: nil, providers: nil,
                   version: nil, plugin_download_url: nil, ignore_changes: nil,
                   additional_secret_outputs: nil, delete_before_replace: nil,
                   replace_on_changes: nil, retain_on_delete: nil, deleted_with: nil,
                   custom_timeouts: nil, import: nil, aliases: nil)
      @parent = parent
      @depends_on = depends_on
      @protect = protect
      @provider = provider
      @providers = providers
      @version = version
      @plugin_download_url = plugin_download_url
      @ignore_changes = ignore_changes
      @additional_secret_outputs = additional_secret_outputs
      @delete_before_replace = delete_before_replace
      @replace_on_changes = replace_on_changes
      @retain_on_delete = retain_on_delete
      @deleted_with = deleted_with
      @custom_timeouts = custom_timeouts
      @import = import
      @aliases = aliases
    end

    # Combines two option sets, with `overrides` winning.
    #
    # This is what lets a component pass its own options down to its children while
    # letting each child override individual settings. `depends_on` concatenates rather
    # than replacing, because dependencies are additive by nature -- a child that declares
    # its own dependency still depends on whatever its parent did.
    #
    # @return [ResourceOptions] a new instance; neither input is modified
    def self.merge(base, overrides)
      return dup_of(overrides) if base.nil?
      return dup_of(base) if overrides.nil?

      merged = dup_of(base)
      SCALAR_FIELDS.each do |field|
        value = overrides.public_send(field)
        merged.public_send(:"#{field}=", value) unless value.nil?
      end

      merged.depends_on = concat_optional(base.depends_on, overrides.depends_on)
      merged.providers = merge_providers(base.providers, overrides.providers)
      merged.aliases = concat_optional(base.aliases, overrides.aliases)
      merged
    end

    SCALAR_FIELDS = %i[
      parent protect provider version plugin_download_url ignore_changes
      additional_secret_outputs delete_before_replace replace_on_changes
      retain_on_delete deleted_with custom_timeouts import
    ].freeze

    def self.dup_of(options)
      return nil if options.nil?

      copy = allocate
      options.instance_variables.each do |ivar|
        copy.instance_variable_set(ivar, options.instance_variable_get(ivar))
      end
      copy
    end
    private_class_method :dup_of

    def self.concat_optional(base, overrides)
      return overrides if base.nil?
      return base if overrides.nil?

      Array(base) + Array(overrides)
    end
    private_class_method :concat_optional

    def self.merge_providers(base, overrides)
      return overrides if base.nil?
      return base if overrides.nil?

      normalize_providers(base).merge(normalize_providers(overrides))
    end
    private_class_method :merge_providers

    # `providers` may be given as a Hash of package name to provider, or as an Array that
    # is keyed by each provider's package. Normalizing to a Hash up front means merging
    # only has to handle one shape.
    def self.normalize_providers(providers)
      return providers if providers.is_a?(Hash)

      Array(providers).to_h { |provider| [provider.package, provider] }
    end
    private_class_method :normalize_providers
  end
end
