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

require_relative "errors"
require_relative "output"
require_relative "resource_options"

module Pulumi
  # A resource managed by Pulumi.
  #
  # Constructing one *declares* it. The constructor returns immediately, before the engine
  # has done anything, and every value the provider computes -- ids, ARNs, endpoints --
  # arrives later as an {Output}.
  #
  # There is no separate "compile" and "converge" step here, and no `lazy` to reach for.
  # A Pulumi program runs top to bottom exactly once; deferral is expressed by the
  # dependency graph the Outputs describe, not by a phase boundary.
  class Resource
    # @return [Output<String>] the engine-assigned URN, unique within the stack
    attr_reader :urn

    # @return [String] the Pulumi type token, e.g. "aws:s3/bucket:Bucket"
    attr_reader :pulumi_type

    # @return [String] the logical name given at construction
    attr_reader :pulumi_name

    # @api private
    # @return [Concurrent::Promises::Future<Runtime::Registration>]
    attr_reader :registration

    # @param type [String] the Pulumi type token
    # @param name [String] a logical name, unique among siblings
    # @param custom [Boolean] whether a provider manages this resource directly
    # @param props [Hash] the resource's inputs
    # @param opts [ResourceOptions, nil]
    # @yield [args] an optional configuration block; see {Args}
    def initialize(type, name, custom:, props: {}, opts: nil, &block)
      raise ArgumentError, "resource type must not be empty" if type.nil? || type.empty?
      raise ArgumentError, "resource name must not be empty" if name.nil? || name.empty?

      props = OpenArgs.build(symbolize(props), &block).to_h if block

      @pulumi_type = type
      @pulumi_name = name
      @custom = custom
      @options = opts || ResourceOptions.new

      # The parent is resolved here, synchronously, rather than inside the registration
      # that follows. Registration runs asynchronously, and the ambient "current root"
      # only holds while the program is executing -- by the time a late registration ran,
      # the program could already have finished and cleared it, silently producing
      # top-level resources. Where a resource was declared is a fact about construction,
      # so it is captured at construction.
      @parent = @options.parent || Runtime.default_parent_for(self)

      # Captured for the same reason as the parent: it is read from the registration
      # continuation, which runs on a worker thread after the program may have finished.
      @dry_run = Runtime.settings.dry_run?

      # Children are recorded so that `depends_on: [some_component]` can be expanded into
      # the resources that actually do the work. A component has no provider behind it, so
      # depending on the component alone would order nothing.
      @children = []
      @children_mutex = Mutex.new
      @parent&.add_child(self)

      @registration = Runtime.register_resource(self, props: props, opts: @options, parent: @parent)
      @urn = derived_output(&:urn)
    end

    # @return [Boolean] whether a provider manages this resource directly, as opposed to
    #   it being a purely logical grouping of other resources
    def custom?
      @custom
    end

    # @api private
    def add_child(child)
      @children_mutex.synchronize { @children << child }
    end

    # @api private
    # @return [Array<Resource>] a snapshot of the children declared so far
    def children
      @children_mutex.synchronize { @children.dup }
    end

    # The value a provider computed for one of this resource's output properties.
    #
    # Generated SDKs wrap this in named readers (`bucket.arn`); until they exist, programs
    # using a raw type token call it directly.
    #
    # @param name [String, Symbol]
    # @return [Output]
    def output(name)
      key = name.to_s
      derived_output { |state| state.outputs.fetch(key) { unresolved } }
    end

    # @return [Output<Hash>] every output property the provider returned
    def outputs
      derived_output(&:outputs)
    end

    def inspect
      "#<#{self.class.name} #{pulumi_type} #{pulumi_name.inspect}>"
    end

    private

    # Args are keyed by Symbol; a props hash may legitimately use either.
    def symbolize(props)
      props.to_h { |key, value| [key.to_sym, value] }
    end

    # What a value the engine did not return should resolve to.
    #
    # During a preview the provider has not run, so an absent value is not "nothing" -- it
    # is not yet knowable. Resolving it to nil would let an apply run against a placeholder
    # and produce a preview that disagrees with the update that follows. Outside a preview,
    # an absent value really is absent.
    #
    # `dry_run?` is read from @dry_run, captured at construction, rather than from
    # Runtime.settings. This runs inside the registration continuation on a worker thread,
    # where the ambient runtime may already have been torn down -- the same hazard that
    # made the parent resolve to nothing before it too was captured eagerly.
    def unresolved
      @dry_run ? Runtime::RPC::UNKNOWN_VALUE : nil
    end

    # Builds an Output over some part of the eventual registration result.
    #
    # This is the only place a deserialized value becomes an Output, which is what lets the
    # unknown check below work: deserialization yields plain data plus markers, all of
    # which stay inspectable. Wrapping earlier would hide an unknown inside an opaque
    # Output and silently make it look known.
    #
    # Everything derived from a registration also depends on this resource, so the
    # dependency is attached here once rather than at each call site. A registration the
    # engine elided -- during a targeted update, say -- yields unknown throughout.
    def derived_output
      future = registration.then do |state|
        value = state.unknown ? Runtime::RPC::UNKNOWN_VALUE : yield(state)

        data =
          if Runtime::RPC.contains_unknown?(value)
            Output::Data.unknown(secret: Runtime::RPC.contains_secret?(value), resources: [self])
          else
            Output::Data.known(
              Runtime::RPC.unwrap_secrets(value),
              secret: Runtime::RPC.contains_secret?(value),
              resources: [self]
            )
          end

        Concurrent::Promises.fulfilled_future(data)
      end

      Output.new(future.flat_future)
    end
  end

  # A resource whose lifecycle a provider manages directly.
  class CustomResource < Resource
    # @return [Output<String>] the provider-assigned id
    attr_reader :id

    # @param type [String] the Pulumi type token, e.g. "aws:s3/bucket:Bucket"
    # @param name [String] a logical name
    # @param props [Hash] the resource's inputs
    # @param opts [ResourceOptions, nil]
    def initialize(type, name, props = {}, opts = nil, &)
      super(type, name, custom: true, props: props, opts: opts, &)
      # The engine reports an empty id for a resource it has not created yet, which during
      # a preview means "not knowable", not "no id".
      @id = derived_output { |state| state.id.nil? ? unresolved : state.id }
    end
  end

  # A resource that groups other resources without being managed by a provider itself.
  #
  # Subclass it to package a piece of infrastructure:
  #
  #   class Website < Pulumi::ComponentResource
  #     def initialize(name, opts: nil)
  #       super("myorg:web:Website", name, opts: opts)
  #       bucket = Pulumi::CustomResource.new(
  #         "aws:s3/bucket:Bucket", "#{name}-bucket", {},
  #         Pulumi::ResourceOptions.new(parent: self))
  #       register_outputs(bucket_name: bucket.output("bucket"))
  #     end
  #   end
  #
  # This is the shape Chef's custom resources had -- a reusable unit with inputs and
  # outputs -- expressed with plain subclassing rather than a `provides`/`action` DSL.
  class ComponentResource < Resource
    def initialize(type, name, props = {}, opts = nil, &)
      super(type, name, custom: false, props: props, opts: opts, &)
      @outputs_registered = false
    end

    # Publishes this component's outputs to the engine.
    #
    # Call it once, at the end of the constructor, after the children exist.
    def register_outputs(outputs = {})
      raise Error, "register_outputs may only be called once per component" if @outputs_registered

      @outputs_registered = true
      Runtime.register_resource_outputs(self, outputs)
    end
  end

  # A resource representing an explicitly configured instance of a provider, so that
  # resources can be pointed at a particular account, region or endpoint.
  class ProviderResource < CustomResource
    # @return [String] the package this provider serves, e.g. "aws"
    attr_reader :package

    def initialize(package, name, props = {}, opts = nil, &)
      @package = package
      super("pulumi:providers:#{package}", name, props, opts, &)
    end
  end
end
