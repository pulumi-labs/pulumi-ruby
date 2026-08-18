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

require_relative "../asset"
require_relative "../output"
require_relative "proto"

module Pulumi
  module Runtime
    # Translation between Ruby values and the protobuf `Struct`s the engine speaks.
    #
    # A protobuf Struct can only carry JSON's types, so everything richer -- secrets,
    # assets, references to other resources, values that aren't known yet -- is encoded as
    # a map carrying a magic signature key. Those signatures are a wire format shared by
    # every Pulumi SDK; they are defined canonically in
    # pulumi/pulumi's sdk/go/common/resource/sig/sig.go and must match exactly.
    #
    # Serialization is *blocking*: it waits on the futures behind any Outputs it meets
    # rather than returning a future of its own. That is safe because every caller runs on
    # the io executor, which grows on demand, and it is what lets this file stay a
    # straightforward recursive walk instead of the promise-threading the async SDKs need.
    module RPC
      # Identifies a map as an encoded special value rather than a plain object.
      SIG_KEY = "4dabf18193072939515e22adb298388d"

      ASSET_SIG              = "c44067f5952c0a294b673a41bacd8c17"
      ARCHIVE_SIG            = "0def7320c3a5731c473e5ecbe6d01bc7"
      SECRET_SIG             = "1b47061264138c4ac30d75fd1eb44270"
      RESOURCE_REFERENCE_SIG = "5cf8f73096256a8f31e491e813e4eb8e"
      OUTPUT_VALUE_SIG       = "d0e6a833031e9bbcd3f4e8bde6ca49a4"
      BYTE_STRING_SIG        = "803fd3297a5875dc03ca845dda5d2a98"

      # Stands in for a value that will not exist until after a `pulumi up`. During a
      # preview the engine substitutes this for anything it cannot yet compute.
      UNKNOWN = "04da6b54-80e4-46f7-96ec-b56ff0331ba9"

      # What the sentinel deserializes to.
      #
      # This is deliberately its own object rather than nil: "the engine cannot tell me
      # this yet" and "the value is null" are different facts, and collapsing them would
      # make a preview resolve outputs to nil that will be populated on the next `up`.
      UNKNOWN_VALUE = Object.new.tap do |marker|
        marker.define_singleton_method(:inspect) { "#<Pulumi unknown>" }
        marker.define_singleton_method(:to_s) { "#<Pulumi unknown>" }
      end.freeze

      # Marks a deserialized value as secret.
      #
      # Deserialization deliberately produces plain data plus markers rather than Outputs.
      # An Output is opaque -- nothing can see through it to ask "does this contain an
      # unknown?" -- so building one here loses unknown-ness for good when the engine sends
      # secret(unknown), which is exactly what it sends for a secret property during a
      # preview. Markers keep the value inspectable until Resource#derived_output, the one
      # place that turns it into an Output.
      Secret = ::Data.define(:value)

      # Options controlling how a value is put on the wire. These mostly track what the
      # engine on the other end has told us it understands, so that the SDK degrades
      # rather than sending something the receiver will reject.
      Options = ::Data.define(
        # Whether the receiver understands the secret signature. When false, secrets are
        # sent in the clear -- the engine is older than the feature.
        :keep_secrets,
        # Whether the receiver understands resource references. When false a resource is
        # sent as its bare id (custom) or urn (component).
        :keep_resources,
        # Whether to send Outputs as output-value maps carrying their dependencies, rather
        # than resolving them to plain values. Used for remote components and Call.
        :keep_output_values,
        # Whether the receiver can accept strings containing non-UTF-8 bytes.
        :keep_byte_string,
        # Whether resources encountered while serializing should be added to the
        # dependency set. Call/Construct exclude them because the dependency is already
        # expressed by the output value's own dependency list.
        :exclude_resource_refs_from_deps
      ) do
        def self.default(**overrides)
          new(keep_secrets: true,
              keep_resources: true,
              keep_output_values: false,
              keep_byte_string: false,
              exclude_resource_refs_from_deps: false, **overrides)
        end
      end

      # The result of serializing one property: its protobuf value plus the resources that
      # value turned out to depend on.
      Serialized = ::Data.define(:value, :resources)

      class << self
        # Serializes a property map for an RPC.
        #
        # @param properties [Hash] the resource's inputs
        # @param options [Options]
        # @return [Array(Google::Protobuf::Struct, Hash{String => Array<Resource>})]
        #   the encoded struct, and the per-property dependencies the engine needs in
        #   order to sequence operations correctly
        def serialize_properties(properties, options = Options.default)
          fields = {}
          dependencies = {}

          properties.each do |key, value|
            name = key.to_s
            serialized = serialize_value(value, options)

            # A property that resolves to nothing is omitted rather than sent as null:
            # providers distinguish "unset" from "explicitly null", and sending null
            # would spuriously diff against an absent value.
            next if serialized.value.nil?

            fields[name] = serialized.value
            dependencies[name] = serialized.resources unless serialized.resources.empty?
          end

          [Google::Protobuf::Struct.new(fields: fields), dependencies]
        end

        # Serializes a single value.
        #
        # @return [Serialized] whose `value` is a Google::Protobuf::Value, or nil to mean
        #   "omit this property entirely"
        def serialize_value(value, options = Options.default)
          case value
          when Output          then serialize_output(value, options)
          when Asset           then wrap(asset_struct(value, options))
          when Archive         then wrap(archive_struct(value, options))
          when ::Array         then serialize_array(value, options)
          when ::Hash          then serialize_hash(value, options)
          when ::String        then wrap(string_value(value, options))
          when ::Symbol        then wrap(string_value(value.to_s, options))
          when ::Integer, ::Float then wrap(Google::Protobuf::Value.new(number_value: value.to_f))
          when true, false     then wrap(Google::Protobuf::Value.new(bool_value: value))
          # A nil property is *absent*, not null. Returning no value lets
          # serialize_properties drop it; the collection cases below substitute an
          # explicit null where position matters.
          when nil             then wrap(nil)
          when UNKNOWN_VALUE   then wrap(unknown_value)
          when Secret          then serialize_secret(value, options)
          else
            serialize_other(value, options)
          end
        end

        # Whether a value is, or contains anywhere within it, something the engine could
        # not compute yet. A resource output containing a nested unknown must itself be
        # treated as unknown, because a program cannot safely read any part of it.
        def contains_unknown?(value)
          case value
          when UNKNOWN_VALUE then true
          when Secret  then contains_unknown?(value.value)
          when ::Array then value.any? { |element| contains_unknown?(element) }
          when ::Hash  then value.any? { |_, element| contains_unknown?(element) }
          else false
          end
        end

        # Whether a value carries a secret anywhere within it. Secretness is contagious:
        # a structure with one secret field is secret as a whole, because nothing weaker
        # would keep it out of plaintext state.
        def contains_secret?(value)
          case value
          when Secret  then true
          when ::Array then value.any? { |element| contains_secret?(element) }
          when ::Hash  then value.any? { |_, element| contains_secret?(element) }
          else false
          end
        end

        # Strips Secret markers, leaving plain data. Callers pair this with
        # contains_secret? so the secretness is carried on the Output instead.
        def unwrap_secrets(value)
          case value
          when Secret  then unwrap_secrets(value.value)
          when ::Array then value.map { |element| unwrap_secrets(element) }
          when ::Hash  then value.transform_values { |element| unwrap_secrets(element) }
          else value
          end
        end

        # Deserializes a protobuf Struct back into plain Ruby values.
        #
        # @param struct [Google::Protobuf::Struct]
        # @return [Hash{String => Object}]
        def deserialize_properties(struct)
          return {} if struct.nil?

          map_fields(struct.fields) { |value| deserialize_value(value) }
        end

        # Converts a protobuf map field into a plain Hash, applying the block to each value.
        #
        # This exists because Google::Protobuf::Map looks like a Hash but *silently ignores*
        # a block passed to #to_h, handing back the raw protobuf values as though the block
        # had never been given. That fails quietly and produces subtly wrong data rather
        # than an error, so every walk over a protobuf map goes through here.
        #
        # Map diverges from Hash elsewhere too -- it has no #key?, for instance. Presence
        # checks below are written as `fields["x"]` rather than #key?/#has_key?, which is
        # exact here because a protobuf map returns nil for a missing key and can never
        # hold a Ruby nil as a value.
        def map_fields(fields)
          fields.each_with_object({}) { |(key, value), result| result[key] = yield(value) }
        end

        # Deserializes a single protobuf Value.
        def deserialize_value(value)
          case value.kind
          when :null_value   then nil
          when :bool_value   then value.bool_value
          when :number_value then normalize_number(value.number_value)
          when :string_value then deserialize_string(value.string_value)
          when :list_value   then value.list_value.values.map { |v| deserialize_value(v) }
          when :struct_value then deserialize_struct(value.struct_value)
          else
            raise Error, "unrecognized protobuf value kind: #{value.kind}"
          end
        end

        private

        def wrap(value, resources = [])
          Serialized.new(value: value, resources: resources)
        end

        # A Secret marker round-trips as the secret signature, so a value read back from
        # the engine and passed to another resource stays secret.
        def serialize_secret(secret, options)
          inner = serialize_value(secret.value, options)
          return inner unless options.keep_secrets

          wrap(secret_struct(inner.value || unknown_value), inner.resources)
        end

        def serialize_output(output, options)
          # value! re-raises whatever the apply chain threw, so a failure in user code
          # surfaces here with its original backtrace rather than as a serialization error.
          data = output.data_future.value!

          resources = options.exclude_resource_refs_from_deps ? [] : data.resources

          # Output values carry their own known/secret/dependency metadata across the wire,
          # which is how a remote component learns what its inputs depend on. When the
          # receiver doesn't support them, the metadata is flattened away instead.
          return wrap(output_value_struct(data, options), resources) if options.keep_output_values

          # A value that isn't known yet goes on the wire as the sentinel, which is how the
          # engine is told "this will be filled in later".
          inner = data.known ? serialize_value(data.value, options).value : unknown_value

          inner = secret_struct(inner) if data.secret && options.keep_secrets
          wrap(inner, resources)
        end

        def serialize_array(array, options)
          resources = []
          values = array.map do |element|
            serialized = serialize_value(element, options)
            resources.concat(serialized.resources)
            # Unlike a property map, a nil inside a list has to stay: dropping it would
            # silently change the list's length and shift every subsequent index.
            serialized.value || null_value
          end

          wrap(
            Google::Protobuf::Value.new(list_value: Google::Protobuf::ListValue.new(values: values)),
            resources.uniq(&:object_id)
          )
        end

        def serialize_hash(hash, options)
          resources = []
          fields = {}

          hash.each do |key, value|
            serialized = serialize_value(value, options)
            # Only the *top level* omits nils, matching the other SDKs: there "unset" is
            # meaningful to a provider. Inside a nested object a nil is part of the value's
            # shape, so it is sent explicitly.
            fields[key.to_s] = serialized.value || null_value
            resources.concat(serialized.resources)
          end

          wrap(struct_value(fields), resources.uniq(&:object_id))
        end

        # Ruby Strings are byte strings, so a program can perfectly legitimately hold one
        # that isn't valid UTF-8 -- the contents of a binary file, for instance. protobuf's
        # string fields cannot carry those, so they get base64-encoded behind a signature.
        def string_value(string, options)
          utf8 = to_utf8(string)
          return Google::Protobuf::Value.new(string_value: utf8) if utf8

          unless options.keep_byte_string
            raise Error,
                  "a string property contains bytes that are not valid UTF-8, which the receiver " \
                  "does not support"
          end

          struct_value(
            SIG_KEY => Google::Protobuf::Value.new(string_value: BYTE_STRING_SIG),
            "value" => Google::Protobuf::Value.new(string_value: [string].pack("m0"))
          )
        end

        # Returns a UTF-8 String, or nil when the value is genuinely a bag of bytes.
        def to_utf8(string)
          return string if string.encoding == Encoding::UTF_8 && string.valid_encoding?

          # BINARY (ASCII-8BIT) means "raw bytes with no encoding", so reinterpreting is
          # right and transcoding would be meaningless. Any other encoding carries real
          # character semantics, so transcode it properly.
          if string.encoding == Encoding::BINARY
            candidate = string.dup.force_encoding(Encoding::UTF_8)
            return candidate.valid_encoding? ? candidate : nil
          end

          string.encode(Encoding::UTF_8)
        rescue EncodingError
          nil
        end

        def output_value_struct(data, options)
          fields = { SIG_KEY => Google::Protobuf::Value.new(string_value: OUTPUT_VALUE_SIG) }

          # An absent "value" is how the wire format says "unknown" -- distinct from a
          # present null, which means the value is known to be nothing.
          if data.known
            inner = serialize_value(data.value, options.with(keep_output_values: false)).value
            fields["value"] = inner unless inner.nil?
          end

          fields["secret"] = Google::Protobuf::Value.new(bool_value: true) if data.secret

          urns = data.resources.filter_map { |resource| resource_urn(resource) }
          unless urns.empty?
            fields["dependencies"] = Google::Protobuf::Value.new(
              list_value: Google::Protobuf::ListValue.new(
                values: urns.map { |urn| Google::Protobuf::Value.new(string_value: urn) }
              )
            )
          end

          struct_value(fields)
        end

        def secret_struct(inner)
          struct_value(
            SIG_KEY => Google::Protobuf::Value.new(string_value: SECRET_SIG),
            "value" => inner
          )
        end

        def unknown_value
          Google::Protobuf::Value.new(string_value: UNKNOWN)
        end

        def null_value
          Google::Protobuf::Value.new(null_value: :NULL_VALUE)
        end

        def asset_struct(asset, options)
          fields = { SIG_KEY => Google::Protobuf::Value.new(string_value: ASSET_SIG) }

          case asset
          when FileAsset then fields["path"] = Google::Protobuf::Value.new(string_value: asset.path)
          when StringAsset then fields["text"] = string_value(asset.text, options)
          when RemoteAsset  then fields["uri"] = Google::Protobuf::Value.new(string_value: asset.uri)
          else raise Error, "unrecognized asset type: #{asset.class}"
          end

          struct_value(fields)
        end

        def archive_struct(archive, options)
          fields = { SIG_KEY => Google::Protobuf::Value.new(string_value: ARCHIVE_SIG) }

          case archive
          when FileArchive   then fields["path"] = Google::Protobuf::Value.new(string_value: archive.path)
          when RemoteArchive then fields["uri"]  = Google::Protobuf::Value.new(string_value: archive.uri)
          when AssetArchive
            nested = archive.assets.to_h do |name, entry|
              [name.to_s, serialize_value(entry, options).value]
            end
            fields["assets"] = struct_value(nested)
          else raise Error, "unrecognized archive type: #{archive.class}"
          end

          struct_value(fields)
        end

        # Resources are serialized here rather than in the main `case` because Resource is
        # defined in a file that depends on this one; checking by capability keeps the
        # dependency pointing one way.
        def serialize_other(value, options)
          return serialize_resource(value, options) if resource?(value)

          raise Error, "cannot serialize a value of type #{value.class} into a Pulumi property"
        end

        def serialize_resource(resource, options)
          resources = options.exclude_resource_refs_from_deps ? [] : [resource]

          unless options.keep_resources
            # Older engines get the plain identifier they would have understood: a custom
            # resource's id, or a component's urn.
            fallback = resource.custom? ? resource.id : resource.urn
            return wrap(serialize_value(fallback, options).value, resources)
          end

          fields = {
            SIG_KEY => Google::Protobuf::Value.new(string_value: RESOURCE_REFERENCE_SIG),
            "urn" => serialize_value(resource.urn, options).value
          }
          if resource.custom?
            id = serialize_value(resource.id, options).value
            fields["id"] = id unless id.nil?
          end

          wrap(struct_value(fields), resources)
        end

        def resource?(value)
          value.respond_to?(:urn) && value.respond_to?(:custom?)
        end

        def resource_urn(resource)
          data = resource.urn.data_future.value!
          data.known ? data.value : nil
        end

        def struct_value(fields)
          Google::Protobuf::Value.new(struct_value: Google::Protobuf::Struct.new(fields: fields))
        end

        # protobuf has only doubles, so an integer arrives as e.g. 7.0. Ruby programs
        # expect an Integer back -- `count == 3` should hold -- so whole numbers are
        # narrowed. Values outside the exactly-representable integer range are left as
        # Floats rather than silently claiming a precision the wire never had.
        def normalize_number(number)
          return number unless number.finite?
          return number unless number == number.truncate
          return number if number.abs > (2**53)

          number.to_i
        end

        def deserialize_string(string)
          return UNKNOWN_VALUE if string == UNKNOWN

          string
        end

        def deserialize_struct(struct)
          fields = struct.fields
          sig = fields[SIG_KEY]
          return map_fields(fields) { |value| deserialize_value(value) } if sig.nil?

          case sig.string_value
          when SECRET_SIG      then Secret.new(value: deserialize_value(require_field(fields, "value", "secret")))
          when BYTE_STRING_SIG then decode_byte_string(fields)
          when ASSET_SIG       then deserialize_asset(fields)
          when ARCHIVE_SIG     then deserialize_archive(fields)
          when OUTPUT_VALUE_SIG then deserialize_output_value(fields)
          when RESOURCE_REFERENCE_SIG
            # A resource reference deserializes to its plain identity. Rehydrating it into
            # a typed resource object needs generated SDK classes, which do not exist yet.
            { "urn" => deserialize_value(fields["urn"]) }.tap do |ref|
              ref["id"] = deserialize_value(fields["id"]) if fields["id"]
            end
          else
            raise Error, "unrecognized signature #{sig.string_value.inspect} in RPC value"
          end
        end

        def deserialize_output_value(fields)
          # Absent "value" means unknown; see output_value_struct.
          value = fields["value"] ? deserialize_value(fields["value"]) : UNKNOWN_VALUE

          fields["secret"]&.bool_value ? Secret.new(value: value) : value
        end

        # pack("m0")/unpack1("m") are strict base64 in core Ruby -- identical output to
        # Base64.strict_encode64, without depending on the base64 gem, which stopped being
        # a default gem in Ruby 3.4 and so is absent from a strict bundle.
        def decode_byte_string(fields)
          encoded = require_field(fields, "value", "byte string").string_value
          encoded.unpack1("m")
        end

        def deserialize_asset(fields)
          return FileAsset.new(fields["path"].string_value) if fields["path"]
          return StringAsset.new(fields["text"].string_value) if fields["text"]
          return RemoteAsset.new(fields["uri"].string_value) if fields["uri"]

          raise Error, "malformed asset: expected one of path, text or uri"
        end

        def deserialize_archive(fields)
          return FileArchive.new(fields["path"].string_value) if fields["path"]
          return RemoteArchive.new(fields["uri"].string_value) if fields["uri"]

          if fields["assets"]
            assets = map_fields(fields["assets"].struct_value.fields) { |value| deserialize_value(value) }
            return AssetArchive.new(assets)
          end

          raise Error, "malformed archive: expected one of path, uri or assets"
        end

        def require_field(fields, name, description)
          fields[name] or raise Error, "malformed #{description}: missing #{name.inspect}"
        end
      end
    end
  end
end
