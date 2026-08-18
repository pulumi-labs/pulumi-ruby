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
    class << self
      # Calls a provider function and returns its result as an Output.
      #
      # @api private
      # @return [Output<Hash>]
      def invoke(token, args, opts)
        future = run_rpc do
          settings = Runtime.settings

          # An invoke whose arguments are not yet known cannot be answered: the provider
          # would be handed a sentinel and have nothing sensible to do with it. Reporting
          # unknown matches what the engine does and keeps a preview honest.
          next :unknown unless Output.from(args).data_future.value!.known

          # The original args are serialized, not the resolved ones, so that secrets and
          # resource references keep their encoding rather than being flattened by the
          # known-check above.
          serialized, = RPC.serialize_properties(args, settings.rpc_options)

          response = settings.monitor.invoke(
            Pulumirpc::ResourceInvokeRequest.new(
              tok: token,
              args: serialized,
              provider: await_provider_reference(opts.provider),
              version: opts.version.to_s,
              pluginDownloadURL: opts.plugin_download_url.to_s,
              acceptResources: settings.supports?(:resource_references),
              accepts_byte_string: settings.supports?(:byte_string),
              dependsOn: await_dependency_urns(opts.depends_on),
              parent: await_urn(opts.parent)
            )
          )

          raise_invoke_failures(token, response.failures)
          RPC.deserialize_properties(response.return)
        end

        Output.new(future.then { |result| invoke_data(result) }.flat_future)
      end

      private

      def invoke_data(result)
        return Concurrent::Promises.fulfilled_future(Output::Data.unknown) if result == :unknown

        data =
          if RPC.contains_unknown?(result)
            Output::Data.unknown(secret: RPC.contains_secret?(result))
          else
            Output::Data.known(RPC.unwrap_secrets(result), secret: RPC.contains_secret?(result))
          end

        Concurrent::Promises.fulfilled_future(data)
      end

      # A provider rejects bad arguments by naming the properties at fault rather than
      # failing wholesale, so the message repeats that detail rather than flattening it.
      def raise_invoke_failures(token, failures)
        return if failures.nil? || failures.empty?

        details = failures.map { |failure| "#{failure.property}: #{failure.reason}" }
        raise Error, "invoke of #{token} failed:\n\t#{details.join("\n\t")}"
      end
    end
  end
end
