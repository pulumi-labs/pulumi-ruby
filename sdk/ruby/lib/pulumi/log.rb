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

require_relative "runtime/proto"

module Pulumi
  # Sends diagnostics to the engine, so they appear interleaved with resource operations
  # rather than racing them on stdout.
  #
  # Messages can be attached to a resource, which is what makes the CLI show them beneath
  # the right line:
  #
  #   Pulumi::Log.warn("bucket is public", resource: bucket)
  module Log
    # How long to wait for a resource's URN before sending the message unattached. A
    # registration that is taking longer than this is in trouble, and a diagnostic about
    # it is exactly what should not be stuck behind it.
    URN_TIMEOUT_SECONDS = 30

    class << self
      # @param message [String]
      # @param resource [Resource, nil] the resource the message relates to
      # @param ephemeral [Boolean] show transiently rather than in the final output
      def debug(message, resource: nil, ephemeral: false)
        emit(:DEBUG, message, resource, ephemeral)
      end

      def info(message, resource: nil, ephemeral: false)
        emit(:INFO, message, resource, ephemeral)
      end

      def warn(message, resource: nil, ephemeral: false)
        emit(:WARNING, message, resource, ephemeral)
      end

      # Reports an error without stopping the program. To stop, raise instead.
      def error(message, resource: nil, ephemeral: false)
        emit(:ERROR, message, resource, ephemeral)
      end

      private

      def emit(severity, message, resource, ephemeral)
        engine = Runtime.configured? ? Runtime.settings.engine : nil

        # Outside a deployment -- in a unit test, say -- there is no engine to talk to.
        # Falling back to stderr keeps logging usable there instead of raising.
        if engine.nil?
          warn_to_stderr(severity, message)
          return
        end

        engine.log(
          Pulumirpc::LogRequest.new(
            severity: severity,
            message: message.to_s,
            urn: resource_urn(resource).to_s,
            ephemeral: ephemeral
          )
        )
        nil
      end

      # Waits for the resource's URN so the CLI can file the message under the right
      # resource. This cannot deadlock: a URN resolves when the registration RPC returns,
      # and a registration never depends on a log call.
      #
      # A resource whose registration failed still has something worth saying about it, so
      # a rejected or unknown URN degrades to an unattached message rather than raising --
      # logging must never be the thing that breaks a program.
      def resource_urn(resource)
        return nil if resource.nil?

        data = resource.urn.data_future.value!(URN_TIMEOUT_SECONDS)
        return nil if data.nil? || !data.known

        data.value
      rescue StandardError
        nil
      end

      def warn_to_stderr(severity, message)
        Kernel.warn("[pulumi #{severity.to_s.downcase}] #{message}")
      end
    end
  end
end
