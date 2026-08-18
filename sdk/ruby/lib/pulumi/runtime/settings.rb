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

require_relative "proto"
require_relative "rpc"

module Pulumi
  module Runtime
    # Everything the SDK needs to know about the deployment it is part of: which stack it
    # is running against, how to reach the engine, and which protocol features the engine
    # on the other end understands.
    #
    # This is read-only once established. Chef's `node` was a globally mutable bag whose
    # provenance became unanswerable; ambient state here is deliberately write-once,
    # installed before the program runs and never modified by it.
    class Settings
      attr_reader :project, :stack, :organization, :dry_run, :parallel,
                  :root_directory, :monitor, :engine, :config, :config_secret_keys

      # Features the SDK cares about, mapped to their enum symbol in resource.proto. Kept
      # as an explicit list rather than reading the whole enum so that adding a feature
      # upstream doesn't silently change behaviour here.
      FEATURES = {
        secrets: :RESOURCE_MONITOR_FEATURE_SECRETS,
        resource_references: :RESOURCE_MONITOR_FEATURE_RESOURCE_REFERENCES,
        output_values: :RESOURCE_MONITOR_FEATURE_OUTPUT_VALUES,
        alias_specs: :RESOURCE_MONITOR_FEATURE_ALIAS_SPECS,
        deleted_with: :RESOURCE_MONITOR_FEATURE_DELETED_WITH,
        transforms: :RESOURCE_MONITOR_FEATURE_TRANSFORMS,
        parameterization: :RESOURCE_MONITOR_FEATURE_PARAMETERIZATION,
        byte_string: :RESOURCE_MONITOR_FEATURE_BYTE_STRING
      }.freeze

      # The string ids the pre-enum SupportsFeature RPC used, for engines older than
      # GetDeploymentInfo.
      LEGACY_FEATURE_IDS = {
        secrets: "secrets",
        resource_references: "resourceReferences",
        output_values: "outputValues",
        alias_specs: "aliasSpecs",
        deleted_with: "deletedWith",
        transforms: "transforms",
        parameterization: "parameterization"
      }.freeze

      def initialize(project:, stack:, organization: "", dry_run: false, parallel: 0,
                     root_directory: nil, monitor: nil, engine: nil,
                     config: {}, config_secret_keys: [])
        @project = project
        @stack = stack
        @organization = organization
        @dry_run = dry_run
        @parallel = parallel
        @root_directory = root_directory
        @monitor = monitor
        @engine = engine
        @config = config.freeze
        @config_secret_keys = config_secret_keys.freeze
        @features = nil
        @features_mutex = Mutex.new
      end

      alias dry_run? dry_run

      # Whether the engine understands a given protocol feature.
      #
      # @param feature [Symbol] one of the keys of {FEATURES}
      def supports?(feature)
        features.include?(feature)
      end

      # The serialization options implied by what the engine supports, so callers never
      # have to assemble them (and can't assemble them inconsistently).
      def rpc_options(**overrides)
        RPC::Options.default(
          keep_secrets: supports?(:secrets),
          keep_resources: supports?(:resource_references),
          keep_byte_string: supports?(:byte_string),
          **overrides
        )
      end

      private

      # The negotiated feature set, computed once.
      #
      # Every resource registration asks about features, and registrations run
      # concurrently on the io pool, so an unguarded lazy initializer would send one
      # negotiation round trip *per resource* -- 500 wasted RPCs for a 500-resource
      # program, all before any real work starts. The mutex makes it exactly one.
      def features
        return @features if @features

        @features_mutex.synchronize { @features ||= negotiate_features }
      end

      # Modern engines report every supported feature in one GetDeploymentInfo call.
      # Older ones only answer the per-feature SupportsFeature probe, so fall back to
      # asking one question at a time rather than assuming nothing is supported.
      def negotiate_features
        query_deployment_info || query_each_feature || Set.new
      end

      def query_deployment_info
        return nil if monitor.nil?

        info = monitor.get_deployment_info(Google::Protobuf::Empty.new)
        supported = info.supportedFeatures.to_a
        FEATURES.each_with_object(Set.new) do |(name, enum), result|
          result << name if supported.include?(enum)
        end
      rescue GRPC::Unimplemented
        nil
      end

      def query_each_feature
        return nil if monitor.nil?

        LEGACY_FEATURE_IDS.each_with_object(Set.new) do |(name, id), result|
          response = monitor.supports_feature(Pulumirpc::SupportsFeatureRequest.new(id: id))
          result << name if response.hasSupport
        rescue GRPC::BadStatus
          # An engine that doesn't recognise a feature id simply doesn't support it.
          nil
        end
      end
    end

    class << self
      # The settings for the running deployment.
      #
      # @raise [Error] if called outside a Pulumi program
      def settings
        @settings or raise Error, "Pulumi runtime is not configured; this code must run " \
                                  "inside a Pulumi program launched by the `pulumi` CLI"
      end

      # @return [Boolean] whether a program is currently running
      def configured?
        !@settings.nil?
      end

      # Installs the settings for a deployment. Called once by the entry point before the
      # user's program runs.
      #
      # @api private
      def configure(settings)
        @settings = settings
      end

      # Asks the engine to check its own version against a range.
      #
      # @api private
      def require_version(range)
        engine = settings.engine
        raise Error, "Pulumi.require_version needs an engine connection" if engine.nil?

        engine.require_pulumi_version(
          Pulumirpc::RequirePulumiVersionRequest.new(pulumi_version_range: range.to_s)
        )
        nil
      end

      # Tears the runtime down. Only useful between tests.
      #
      # @api private
      def reset
        @settings = nil
      end
    end
  end
end
