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
require "json"

require_relative "errors"

module Pulumi
  # A value that will be known once the engine has talked to a provider.
  #
  # Outputs carry four things together, and keeping them together is what makes
  # secretness and dependency tracking correct:
  #
  # * the value itself,
  # * whether it is *known* -- during a preview a value that depends on a resource that
  #   hasn't been created yet has no value at all,
  # * whether it is *secret*, and
  # * which resources it depends on, so the engine can order operations.
  #
  # Reach inside one with {#apply}. The block runs only once the value is known, and its
  # result is wrapped back up in an Output that inherits the secretness and dependencies
  # of its source:
  #
  #   bucket.website_endpoint.apply { |endpoint| "https://#{endpoint}" }
  #
  # There is deliberately no way to synchronously read the value out. That is not an
  # oversight: during a preview there may be no value to read, and a program that could
  # branch on one would produce a plan that doesn't match what `pulumi up` will do.
  class Output
    # The four-tuple an Output resolves to. Kept as a single value rather than four
    # parallel futures so that a consumer can never observe a value without also seeing
    # the secretness and dependencies that came with it.
    #
    # @api private
    Data = ::Data.define(:value, :known, :secret, :resources) do
      def self.known(value, secret: false, resources: EMPTY_RESOURCES)
        new(value: value, known: true, secret: secret, resources: resources)
      end

      def self.unknown(secret: false, resources: EMPTY_RESOURCES)
        new(value: nil, known: false, secret: secret, resources: resources)
      end
    end

    EMPTY_RESOURCES = [].freeze
    private_constant :EMPTY_RESOURCES

    # @api private
    # @return [Concurrent::Promises::Future<Data>]
    attr_reader :data_future

    # @api private
    # Use {Output.from}, {Output.all} or {Output.secret} instead of calling this directly.
    def initialize(data_future)
      @data_future = data_future
    end

    class << self
      # Lifts a plain value into an Output, recursing through Arrays and Hashes so that a
      # structure containing Outputs becomes an Output of a plain structure.
      #
      # @param value [Object] an Output, or any value possibly containing Outputs
      # @return [Output]
      def from(value)
        return value if value.is_a?(Output)

        case value
        when ::Array then lift_array(value)
        when ::Hash  then lift_hash(value)
        else Output.new(Concurrent::Promises.fulfilled_future(Data.known(value)))
        end
      end

      # Combines several Outputs into one Output of an Array, or -- given keyword
      # arguments -- one Output of a Hash.
      #
      #   Output.all(bucket.id, key).apply { |(id, k)| "#{id}/#{k}" }
      #   Output.all(id: bucket.id, key: key).apply { |h| "#{h[:id]}/#{h[:key]}" }
      #
      # @return [Output]
      def all(*args, **kwargs)
        unless args.empty? || kwargs.empty?
          raise ArgumentError, "Output.all takes either positional or keyword arguments, not both"
        end

        return lift_hash(kwargs) unless kwargs.empty?

        lift_array(args)
      end

      # Marks a value as secret. Secretness is sticky: anything derived from a secret
      # Output through {#apply} or {.all} is itself secret.
      #
      # @return [Output]
      def secret(value)
        from(value).with_secret(true)
      end

      # Removes the secret marker from an Output. Use sparingly -- this is how secret
      # material ends up in plaintext state.
      #
      # @return [Output]
      def unsecret(output)
        from(output).with_secret(false)
      end

      # Interpolates Outputs into a string using Kernel#format semantics.
      #
      #   Output.format("https://%s/%s", bucket.endpoint, key)
      #   Output.format("https://%{host}/%{path}", host: endpoint, path: key)
      #
      # This exists because Ruby has no way to intercept string interpolation: `"#{output}"`
      # calls #to_s, which cannot produce a real value. Use this instead.
      #
      # @return [Output<String>]
      def format(format_string, *args, **kwargs)
        unless kwargs.empty?
          return lift_hash(kwargs).apply { |resolved| ::Kernel.format(format_string, **resolved) }
        end

        lift_array(args).apply { |resolved| ::Kernel.format(format_string, *resolved) }
      end

      # Concatenates string-ish values, any of which may be Outputs.
      #
      # @return [Output<String>]
      def concat(*parts)
        lift_array(parts).apply(&:join)
      end

      # Serializes a value to JSON, resolving any Outputs nested inside it first.
      #
      # @return [Output<String>]
      def json_dump(value)
        from(value).apply { |resolved| JSON.generate(resolved) }
      end

      # Parses a JSON string that may itself be an Output.
      #
      # @return [Output]
      def json_parse(text, symbolize_names: false)
        from(text).apply { |resolved| JSON.parse(resolved, symbolize_names: symbolize_names) }
      end

      private

      def lift_array(values)
        combine(values.map { |v| from(v) }) { |resolved| resolved }
      end

      def lift_hash(hash)
        keys = hash.keys
        combine(hash.values.map { |v| from(v) }) { |resolved| keys.zip(resolved).to_h }
      end

      # combine is the single place where several Outputs are merged, so the rules for
      # propagating known/secret/resources exist exactly once. An unknown anywhere makes
      # the result unknown; a secret anywhere makes it secret; dependencies union.
      def combine(outputs, &shape)
        future = Concurrent::Promises
                 .zip_futures(*outputs.map(&:data_future))
                 .then do |*all|
          known = all.all?(&:known)
          secret = all.any?(&:secret)
          resources = merge_resources(all.flat_map(&:resources))

          if known
            Data.known(shape.call(all.map(&:value)), secret: secret, resources: resources)
          else
            Data.unknown(secret: secret, resources: resources)
          end
        end

        Output.new(future)
      end

      def merge_resources(resources)
        return EMPTY_RESOURCES if resources.empty?

        resources.uniq(&:object_id).freeze
      end
    end

    # Transforms the value inside this Output, producing a new Output.
    #
    # The block runs only when the value is known. During a preview, a value that depends
    # on a resource that has not been created yet is unknown, the block is skipped, and
    # the result is an unknown Output -- which is exactly what lets a preview complete
    # without inventing values.
    #
    # If the block itself returns an Output the result is flattened, so applies compose
    # without nesting.
    #
    # @yieldparam value [Object] the resolved value
    # @return [Output]
    def apply(&block)
      raise ArgumentError, "Output#apply requires a block" unless block

      # Every branch must yield a Future, because flat_future raises TypeError on a plain
      # value rather than passing it through.
      future = data_future.then do |data|
        # Skipping the block on unknown is what makes preview work. It also means the
        # block must not be relied on for side effects.
        unless data.known
          next Concurrent::Promises.fulfilled_future(
            Data.unknown(secret: data.secret, resources: data.resources)
          )
        end

        merge_applied(data, block.call(data.value))
      end

      Output.new(track(future.flat_future))
    end

    # Recovers from an error raised inside a preceding {#apply}.
    #
    # @yieldparam error [Exception]
    # @return [Output]
    def rescue_apply(&block)
      raise ArgumentError, "Output#rescue_apply requires a block" unless block

      # `rescue` passes a fulfilled value straight through, so the success path is wrapped
      # in a future first; that way both paths hand flat_future the Future it requires.
      future = data_future
               .then { |data| Concurrent::Promises.fulfilled_future(data) }
               .rescue { |error| Output.from(block.call(error)).data_future }
               .flat_future

      Output.new(track(future))
    end

    # @api private
    # Returns a copy of this Output with its secret flag forced to the given value.
    def with_secret(secret)
      Output.new(data_future.then { |data| data.with(secret: secret) })
    end

    # @api private
    # Returns a copy of this Output that also depends on the given resources.
    def with_resources(resources)
      return self if resources.empty?

      Output.new(data_future.then do |data|
        data.with(resources: (data.resources + resources).uniq(&:object_id).freeze)
      end)
    end

    # Outputs have no meaningful string form -- the value may not exist yet. Rather than
    # raise (which would make `p output` and backtraces unusable), this warns and returns
    # an explanatory placeholder, matching the other Pulumi SDKs. Set
    # PULUMI_ERROR_OUTPUT_STRING=1 to turn it into a hard error while debugging.
    def to_s
      error = OutputToStringError.new
      raise error if %w[1 true].include?(ENV.fetch("PULUMI_ERROR_OUTPUT_STRING", "").downcase)

      warn(error.message)
      error.message
    end

    def inspect
      "#<Pulumi::Output>"
    end

    private

    # Registers a continuation with the runtime so the program cannot exit before it runs.
    #
    # A block passed to #apply can declare resources, and until this was here the drain
    # could conclude while such a block was still queued -- leaving the resource
    # unregistered, which the engine reads as "deleted from the program". Outside a
    # deployment (a unit test constructing Outputs directly) there is nothing to tell.
    def track(future)
      return future unless Runtime.configured?

      Runtime.rpc_manager.track_side_effects(future)
    end

    # Folds the result of an apply block back into the chain, flattening a nested Output
    # and carrying the source's secretness and dependencies onto the result.
    def merge_applied(source, result)
      inner = Output.from(result)
      inner.data_future.then do |data|
        data.with(
          secret: data.secret || source.secret,
          resources: (source.resources + data.resources).uniq(&:object_id).freeze
        )
      end
    end
  end
end
