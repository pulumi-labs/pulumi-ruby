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

require "concurrent"

require_relative "proto"
require_relative "rpc"
require_relative "settings"

module Pulumi
  module Runtime
    # What the engine returned for a resource registration.
    Registration = ::Data.define(:urn, :id, :outputs, :unknown)

    class << self
      # Registers a resource with the engine.
      #
      # Returns immediately with a future rather than blocking, which is what lets a
      # program declare a whole graph in a few milliseconds and have the engine work on
      # independent resources in parallel. The work happens on the io executor, where
      # blocking on an input's Output is safe because the pool grows on demand.
      #
      # @api private
      # @return [Concurrent::Promises::Future<Registration>]
      def register_resource(resource, props:, opts:, parent:)
        run_rpc do
          settings = Runtime.settings
          options = settings.rpc_options
          object, property_dependencies = RPC.serialize_properties(props, options)

          request = Pulumirpc::RegisterResourceRequest.new(
            type: resource.pulumi_type,
            name: resource.pulumi_name,
            custom: resource.custom?,
            object: object,
            parent: await_urn(parent),
            provider: await_provider_reference(opts.provider),
            providers: await_provider_references(opts.providers),
            dependencies: await_dependency_urns(opts.depends_on),
            propertyDependencies: property_dependency_map(property_dependencies),
            # Field naming here is inconsistent in the proto itself -- the older fields are
            # camelCase and the newer ones snake_case -- so these are spelled exactly as
            # register_resource_request_spec.rb asserts they exist.
            acceptSecrets: settings.supports?(:secrets),
            acceptResources: settings.supports?(:resource_references),
            accepts_byte_string: settings.supports?(:byte_string),
            supportsPartialValues: false,
            # Tells the engine to report a skipped or failed registration in the response's
            # Result rather than failing the whole deployment, which is what makes
            # `--continue-on-error` and targeted updates work.
            supportsResultReporting: true,
            **lifecycle_fields(opts)
          )

          response = settings.monitor.register_resource(request)
          registration_from(response)
        end
      end

      # Publishes a component's outputs once its children have been declared.
      #
      # @api private
      def register_resource_outputs(resource, outputs)
        run_rpc do
          settings = Runtime.settings
          struct, = RPC.serialize_properties(outputs, settings.rpc_options)

          # The URN has to exist before outputs can be attached to it, so this waits on
          # the component's own registration rather than racing it.
          urn = resource.urn.data_future.value!.value
          settings.monitor.register_resource_outputs(
            Pulumirpc::RegisterResourceOutputsRequest.new(urn: urn, outputs: struct)
          )
          nil
        end
      end

      # @api private
      # @return [RPCManager] the tracker for the running program
      def rpc_manager
        @rpc_manager ||= RPCManager.new
      end

      # @api private
      def reset_rpc_manager
        @rpc_manager = RPCManager.new
      end

      private

      # Runs an RPC on the io executor and registers it with the manager, so the program
      # cannot exit before it completes.
      def run_rpc(&)
        rpc_manager.track(Concurrent::Promises.future_on(:io, &))
      end

      def registration_from(response)
        case response.result
        when :FAIL
          raise Error, "resource registration failed"
        when :SKIP
          # The engine chose not to perform this registration -- a targeted update that
          # excluded it, for instance. Its outputs are unknowable, not empty.
          return Registration.new(urn: "", id: nil, outputs: {}, unknown: true)
        end

        Registration.new(
          urn: response.urn,
          id: response.id.empty? ? nil : response.id,
          outputs: RPC.deserialize_properties(response.object),
          unknown: response.unknown
        )
      end

      def property_dependency_map(dependencies)
        dependencies.each_with_object({}) do |(name, resources), result|
          urns = expand_dependencies(resources).filter_map { |resource| resolved_urn(resource) }
          next if urns.empty?

          # Request and response each declare their own PropertyDependencies message; they
          # are structurally identical but not interchangeable.
          result[name] = Pulumirpc::RegisterResourceRequest::PropertyDependencies.new(urns: urns)
        end
      end

      def await_urn(resource)
        return "" if resource.nil?

        resolved_urn(resource).to_s
      end

      # Expands a dependency list into the URNs the engine should order against.
      #
      # A component is not a thing a provider creates, so depending on one has to mean
      # depending on everything it contains. Both the Go and Python SDKs expand components
      # into their children and drop the component itself; the engine does no expansion of
      # its own, so a component URN here would order against nothing.
      def await_dependency_urns(depends_on)
        expand_dependencies(Array(depends_on)).filter_map { |resource| resolved_urn(resource) }
      end

      def expand_dependencies(resources, seen = [])
        resources.each_with_object(seen) do |resource, result|
          next if result.any? { |existing| existing.equal?(resource) }

          if resource.custom?
            result << resource
          else
            expand_dependencies(resource.children, result)
          end
        end
      end

      def resolved_urn(resource)
        data = resource.urn.data_future.value!
        data.known ? data.value : nil
      end

      # A provider is referenced as "<urn>::<id>", the format the engine uses to identify
      # a specific configured provider instance.
      def await_provider_reference(provider)
        return "" if provider.nil?

        urn = resolved_urn(provider)
        id = provider.id.data_future.value!
        return "" if urn.nil? || !id.known

        "#{urn}::#{id.value}"
      end

      def await_provider_references(providers)
        ResourceOptions.send(:normalize_providers, providers).transform_values do |provider|
          await_provider_reference(provider)
        end
      end

      # Options that describe how the engine should manage the resource rather than what
      # the provider should do with it. Absent values are left off entirely so the engine
      # sees "unspecified" rather than an explicit default.
      def lifecycle_fields(opts)
        fields = {}
        fields[:protect] = opts.protect unless opts.protect.nil?
        fields[:version] = opts.version if opts.version
        fields[:pluginDownloadURL] = opts.plugin_download_url if opts.plugin_download_url
        fields[:ignoreChanges] = Array(opts.ignore_changes) if opts.ignore_changes
        fields[:additionalSecretOutputs] = Array(opts.additional_secret_outputs) if opts.additional_secret_outputs
        fields[:replaceOnChanges] = Array(opts.replace_on_changes) if opts.replace_on_changes
        fields[:retainOnDelete] = opts.retain_on_delete unless opts.retain_on_delete.nil?
        fields[:importId] = opts.import if opts.import
        fields[:deletedWith] = await_urn(opts.deleted_with) if opts.deleted_with
        fields[:aliasURNs] = Array(opts.aliases).map(&:to_s) if opts.aliases

        unless opts.delete_before_replace.nil?
          fields[:deleteBeforeReplace] = opts.delete_before_replace
          fields[:deleteBeforeReplaceDefined] = true
        end

        if opts.custom_timeouts
          fields[:customTimeouts] = Pulumirpc::RegisterResourceRequest::CustomTimeouts.new(
            create: opts.custom_timeouts.create.to_s,
            update: opts.custom_timeouts.update.to_s,
            delete: opts.custom_timeouts.delete.to_s
          )
        end

        fields
      end
    end
  end
end
