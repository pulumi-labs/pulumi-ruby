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

require_relative "errors"
require_relative "output"
require_relative "runtime/proto"
require_relative "runtime/resource"
require_relative "runtime/rpc"
require_relative "runtime/settings"
require_relative "runtime/stack"

module Pulumi
  # Runs Pulumi programs against a fake engine so they can be unit tested.
  #
  #   class MyMocks < Pulumi::Testing::Mocks
  #     def new_resource(args)
  #       ["#{args.name}-id", args.inputs.merge("arn" => "arn:fake:#{args.name}")]
  #     end
  #   end
  #
  #   result = Pulumi::Testing.run(MyMocks.new) do
  #     bucket = Pulumi::CustomResource.new("aws:s3/bucket:Bucket", "b", { acl: "private" })
  #     Pulumi.export "arn", bucket.output("arn")
  #   end
  #
  #   expect(Pulumi::Testing.value(result.exports["arn"])).to eq("arn:fake:b")
  #
  # The fake engine sits at the real RPC boundary: a program under test serializes its
  # inputs and deserializes its outputs through exactly the same code a deployment uses.
  # ChefSpec ran recipes with all resource actions disabled, which meant a green unit test
  # said only that the code *intended* something -- the interesting half was untestable.
  # Testing at the wire boundary avoids that: everything except the provider is real.
  module Testing
    # What a mock is told about a resource being created.
    ResourceArgs = ::Data.define(:type, :name, :inputs, :provider, :id, :custom, :parent)

    # What a mock is told about a provider function being invoked.
    InvokeArgs = ::Data.define(:token, :args, :provider)

    # Subclass and override to describe what the cloud would have done.
    class Mocks
      # @param args [ResourceArgs]
      # @return [Array(String, Hash)] the resource's id and its output properties
      def new_resource(args)
        ["#{args.name}-id", args.inputs]
      end

      # @param args [InvokeArgs]
      # @return [Hash] what the provider function would have returned
      def invoke(args)
        _ = args
        {}
      end
    end

    # What a mocked run produced.
    Result = ::Data.define(:exports, :resources) do
      # The resource registered under a given logical name.
      #
      # @return [RegisteredResource, nil]
      def resource(name)
        resources.find { |r| r.name == name }
      end
    end

    # A record of one registration the program performed.
    RegisteredResource = ::Data.define(:type, :name, :urn, :id, :inputs, :outputs, :parent)

    class << self
      # Runs a block as though it were a Pulumi program.
      #
      # @param mocks [Mocks]
      # @param project [String]
      # @param stack [String]
      # @param dry_run [Boolean] simulate `pulumi preview` rather than `pulumi up`
      # @param config [Hash{String => String}] keyed as "namespace:name"
      # @param stack_outputs [Hash{String => Hash}] outputs a StackReference should find,
      #   keyed by referenced stack name
      # @param secret_stack_outputs [Array<String>] which of those the other stack marked secret
      # @return [Result]
      def run(mocks = Mocks.new, project: "project", stack: "stack", dry_run: false, config: {},
              stack_outputs: {}, secret_stack_outputs: [], &)
        monitor = MockMonitor.new(mocks, project: project, stack: stack, dry_run: dry_run,
                                         stack_outputs: stack_outputs,
                                         secret_stack_outputs: secret_stack_outputs)
        previous = Runtime.configured? ? Runtime.settings : nil

        Runtime.configure(
          Runtime::Settings.new(
            project: project, stack: stack, dry_run: dry_run,
            monitor: monitor, engine: nil, config: config
          )
        )
        Runtime.reset_rpc_manager

        begin
          Runtime.run_in_stack(&)
          Runtime.rpc_manager.drain
          exports = Runtime.exports

          error = Runtime.rpc_manager.error
          raise error if error

          Result.new(exports: exports, resources: monitor.registrations)
        ensure
          Runtime.reset_stack
          previous ? Runtime.configure(previous) : Runtime.reset
        end
      end

      # Resolves an Output to its plain value, for assertions.
      #
      # This exists only for tests. A program cannot do this, because during a deployment
      # the value may genuinely not exist yet.
      #
      # @param output [Object] an Output or a plain value
      # @param timeout [Numeric] seconds to wait
      def value(output, timeout: 10)
        return output unless output.is_a?(Output)

        data = output.data_future.value!(timeout)
        raise Error, "Output did not resolve within #{timeout}s" if data.nil?

        data.value
      end

      # Whether an Output is marked secret.
      def secret?(output, timeout: 10)
        return false unless output.is_a?(Output)

        output.data_future.value!(timeout).secret
      end

      # Whether an Output's value is known. False during a simulated preview for anything
      # derived from a resource.
      def known?(output, timeout: 10)
        return true unless output.is_a?(Output)

        output.data_future.value!(timeout).known
      end
    end

    # Stands in for the engine's resource monitor.
    #
    # It implements the same methods the generated gRPC stub does, so the SDK cannot tell
    # the difference -- which is the point: the serialization the SDK performs here is the
    # serialization it performs for real.
    #
    # @api private
    class MockMonitor
      attr_reader :registrations

      def initialize(mocks, project:, stack:, dry_run: false, stack_outputs: {}, secret_stack_outputs: [])
        @mocks = mocks
        @project = project
        @stack = stack
        @dry_run = dry_run
        @stack_outputs = stack_outputs
        @secret_stack_outputs = secret_stack_outputs
        @registrations = []
        @mutex = Mutex.new
      end

      def get_deployment_info(_request)
        Pulumirpc::DeploymentInfo.new(
          project: @project,
          stack: @stack,
          supportedFeatures: Runtime::Settings::FEATURES.values
        )
      end

      def supports_feature(_request)
        Pulumirpc::SupportsFeatureResponse.new(hasSupport: true)
      end

      def invoke(request)
        result = @mocks.invoke(
          InvokeArgs.new(token: request.tok,
                         args: Runtime::RPC.deserialize_properties(request.args),
                         provider: request.provider)
        )

        returned, = Runtime::RPC.serialize_properties(result || {})
        Pulumirpc::InvokeResponse.new(return: returned)
      end

      def register_resource(request)
        inputs = Runtime::RPC.deserialize_properties(request.object)
        urn = urn_for(request.type, request.name)

        return stack_reference_response(request, urn) if request.type == StackReference::TYPE

        id, outputs =
          if request.custom
            @mocks.new_resource(
              ResourceArgs.new(type: request.type, name: request.name, inputs: inputs,
                               provider: request.provider, id: request.importId,
                               custom: request.custom, parent: request.parent)
            )
          else
            # A component has no provider behind it, so its outputs are whatever it was
            # constructed with; only register_resource_outputs adds to them.
            ["", inputs]
          end

        record(request, urn, id, inputs, outputs)

        outputs = elide_computed(inputs, outputs || {}) if @dry_run
        object, = Runtime::RPC.serialize_properties(outputs || {})

        # During a preview nothing has been created, so there is no id -- the same empty
        # string the engine sends, which the SDK reads as "not knowable yet".
        Pulumirpc::RegisterResourceResponse.new(
          urn: urn, id: @dry_run ? "" : id.to_s, object: object
        )
      end

      def register_resource_outputs(request)
        outputs = Runtime::RPC.deserialize_properties(request.outputs)
        @mutex.synchronize do
          index = @registrations.index { |r| r.urn == request.urn }
          @registrations[index] = @registrations[index].with(outputs: outputs) if index
        end
        Google::Protobuf::Empty.new
      end

      private

      # The engine, not a provider, answers a StackReference. Mocks describe providers, so
      # the referenced stack's outputs come from `stack_outputs` passed to Testing.run.
      def stack_reference_response(request, urn)
        inputs = Runtime::RPC.deserialize_properties(request.object)
        name = inputs["name"]
        outputs = @stack_outputs.fetch(name, {})

        # The engine wraps each secret member *and* lists it in secretOutputNames. The
        # wrapping is what makes the whole map secret on arrival, which is exactly the
        # situation StackReference#output has to unpick -- so the mock has to reproduce it,
        # or a test here would pass while the real thing marked every output secret.
        resolved = {
          "name" => name,
          "outputs" => outputs.to_h do |key, value|
            [key, @secret_stack_outputs.include?(key) ? Output.secret(value) : value]
          end,
          "secretOutputNames" => @secret_stack_outputs
        }

        record(request, urn, name, inputs, resolved)
        object, = Runtime::RPC.serialize_properties(resolved)
        Pulumirpc::RegisterResourceResponse.new(urn: urn, id: name.to_s, object: object)
      end

      # Reproduces what the engine does during a preview: a property the provider computed
      # is unknown, while one echoed back from the inputs is already known.
      #
      # Without this a mocked preview resolves values that a real preview cannot, so a
      # dry_run test would assert behaviour that never happens -- and would have missed
      # that secret(unknown) used to deserialize as known.
      def elide_computed(inputs, outputs)
        outputs.to_h do |key, value|
          computed = !inputs.key?(key)
          [key, computed ? unknown_like(value) : value]
        end
      end

      # Keeps a secret marker on a value that has become unknown, because that combination
      # -- secret and not yet knowable -- is exactly what the engine sends for a generated
      # password during a preview.
      def unknown_like(value)
        return Runtime::RPC::Secret.new(value: Runtime::RPC::UNKNOWN_VALUE) if secret?(value)

        Runtime::RPC::UNKNOWN_VALUE
      end

      def secret?(value)
        return true if value.is_a?(Runtime::RPC::Secret)
        return Testing.secret?(value) if value.is_a?(Output)

        false
      end

      def record(request, urn, id, inputs, outputs)
        @mutex.synchronize do
          @registrations << RegisteredResource.new(
            type: request.type, name: request.name, urn: urn, id: id.to_s,
            inputs: inputs, outputs: outputs || {}, parent: request.parent
          )
        end
      end

      def urn_for(type, name)
        "urn:pulumi:#{@stack}::#{@project}::#{type}::#{name}"
      end
    end
  end
end
