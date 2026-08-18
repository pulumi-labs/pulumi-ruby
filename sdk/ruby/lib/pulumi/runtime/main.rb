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

require "json"

require_relative "proto"
require_relative "resource"
require_relative "settings"
require_relative "stack"

module Pulumi
  module Runtime
    class << self
      # Runs a Pulumi program. Called by the pulumi-language-ruby-exec shim.
      #
      # @api private
      # @param entry_point [String] path to the program, relative to pwd
      # @return [Integer] the process exit code
      def main(entry_point, monitor_address: nil, engine_address: nil, project: nil,
               stack: nil, organization: "", dry_run: false, parallel: 0,
               root_directory: nil, pwd: nil, tracing: nil, program_args: [])
        _ = tracing # accepted for parity with the other language hosts; not wired up yet

        Dir.chdir(pwd) if pwd
        configure_from(
          monitor_address: monitor_address, engine_address: engine_address,
          project: project, stack: stack, organization: organization,
          dry_run: dry_run, parallel: parallel, root_directory: root_directory
        )

        execute(entry_point, program_args)
      end

      private

      def configure_from(monitor_address:, engine_address:, project:, stack:, organization:,
                         dry_run:, parallel:, root_directory:)
        configure(
          Settings.new(
            project: project,
            stack: stack,
            organization: organization,
            dry_run: dry_run,
            parallel: parallel,
            root_directory: root_directory,
            monitor: connect(Pulumirpc::ResourceMonitor::Stub, monitor_address),
            engine: connect(Pulumirpc::Engine::Stub, engine_address),
            config: parse_json_env("PULUMI_CONFIG", {}),
            config_secret_keys: parse_json_env("PULUMI_CONFIG_SECRET_KEYS", [])
          )
        )
        reset_rpc_manager
      end

      def execute(entry_point, program_args)
        previous_argv = ARGV.dup
        ARGV.replace(program_args)

        run_in_stack { load_program(entry_point) }

        # The program reaching its last line does not mean its work is done: resource
        # registrations are still in flight. Exiting now would have the engine tear the
        # deployment down mid-operation.
        rpc_manager.drain

        # A registration that failed leaves its error here rather than in whichever
        # worker thread raised it, so it can be reported as the program's own failure.
        error = rpc_manager.error
        raise error if error

        0
      rescue RunError => e
        # RunError means "the message is the whole story" -- print it and use the exit code
        # that tells the language host not to wrap it in a generic failure.
        Kernel.warn(e.message)
        EXIT_AFTER_SHOWING_USER_ACTIONABLE_MESSAGE
      rescue StandardError, ScriptError => e
        report_uncaught(e, entry_point)
        EXIT_AFTER_SHOWING_USER_ACTIONABLE_MESSAGE
      ensure
        ARGV.replace(previous_argv)
      end

      # Loads the user's program.
      #
      # `load` rather than `require` so that a program can be run more than once in a
      # single process (which the unit-test harness relies on), and with an absolute path
      # so the result doesn't depend on $LOAD_PATH.
      def load_program(entry_point)
        path = File.expand_path(entry_point)
        path = File.join(path, "main.rb") if File.directory?(path)

        unless File.file?(path)
          raise RunError, "could not find the program's entry point at #{path}.\n" \
                          "By default Pulumi looks for main.rb; set `main` in Pulumi.yaml to " \
                          "point somewhere else."
        end

        load(path)
      end

      # Trims the backtrace to the user's own frames. The SDK's internal frames are noise
      # when the mistake is in the program, and burying the useful line under them is a
      # large part of why stack traces get ignored.
      def report_uncaught(error, entry_point)
        Kernel.warn("#{error.class}: #{error.message}")

        program_dir = File.dirname(File.expand_path(entry_point))
        sdk_dir = File.expand_path("../../..", __dir__)

        frames = Array(error.backtrace).reject { |frame| frame.start_with?(sdk_dir) }
        frames = Array(error.backtrace) if frames.empty?

        frames.each { |frame| Kernel.warn("\tfrom #{frame}") }
        Kernel.warn("") if program_dir
      end

      def connect(stub_class, address)
        return nil if address.nil? || address.empty?

        stub_class.new(address, :this_channel_is_insecure, channel_args: GRPC_CHANNEL_ARGS)
      end

      def parse_json_env(name, default)
        raw = ENV.fetch(name, nil)
        return default if raw.nil? || raw.empty?

        JSON.parse(raw)
      end
    end

    # Resource property payloads can be large -- a lambda's source archive, say -- so the
    # 4MB gRPC default is raised to match what the other Pulumi SDKs use.
    GRPC_CHANNEL_ARGS = {
      "grpc.max_receive_message_length" => 1024 * 1024 * 400,
      "grpc.max_send_message_length" => 1024 * 1024 * 400
    }.freeze

    # Exit code the language host reads as "a useful message was already printed".
    EXIT_AFTER_SHOWING_USER_ACTIONABLE_MESSAGE = 32
  end
end
