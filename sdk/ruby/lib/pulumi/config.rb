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

require_relative "errors"
require_relative "output"

module Pulumi
  # Raised when a required configuration value is missing.
  class ConfigMissingError < Error
    attr_reader :key

    def initialize(key)
      @key = key
      super("Missing required configuration variable '#{key}'\n" \
            "\tplease set a value using the command `pulumi config set #{key} <value>`")
    end
  end

  # Raised when a configuration value cannot be read as the requested type.
  class ConfigTypeError < Error
    def initialize(key, value, expected)
      super("Configuration '#{key}' value '#{value}' is not a valid #{expected}")
    end
  end

  # Reads configuration for the running stack.
  #
  #   config = Pulumi.config          # namespaced to the current project
  #   env    = config.require("env")
  #   size   = config.get_integer("size") || 3
  #   token  = config.require_secret("apiToken")
  #
  # Every type comes in four flavours, and they compose rather than each reimplementing the
  # reading and parsing:
  #
  #   get_X          -> the value, or nil
  #   require_X      -> the value, or raises ConfigMissingError
  #   get_secret_X   -> Output of the value marked secret, or nil
  #   require_secret_X -> Output of the value marked secret, or raises
  #
  # There is exactly one source of values here -- what `pulumi config set` recorded for
  # this stack -- and it is read-only. Chef's fifteen levels of attribute precedence made
  # "where did this value come from?" unanswerable without running the whole thing; there
  # is nothing to layer here on purpose.
  class Config
    # @return [String] the namespace configuration keys are read from
    attr_reader :namespace

    # @param namespace [String, nil] defaults to the current project's name
    def initialize(namespace = nil)
      @namespace = namespace || Runtime.settings.project
    end

    # @return [String, nil]
    def get(key) = raw(key)

    # @return [String]
    # @raise [ConfigMissingError]
    def require(key) = required(key) { get(key) }

    # @return [Output<String>, nil]
    def get_secret(key) = as_secret(get(key))

    # @return [Output<String>]
    def require_secret(key) = Output.secret(require(key))

    # @return [Boolean, nil]
    # @raise [ConfigTypeError] if the value is neither "true" nor "false"
    def get_boolean(key)
      coerce(key, "boolean") do |value|
        # Not `value == "true"`: anything else has to be an error rather than false, or a
        # typo silently disables a feature.
        next true if value == "true"
        next false if value == "false"

        nil
      end
    end

    # @return [Boolean]
    def require_boolean(key) = required(key) { get_boolean(key) }

    # @return [Output<Boolean>, nil]
    def get_secret_boolean(key) = as_secret(get_boolean(key))

    # @return [Output<Boolean>]
    def require_secret_boolean(key) = Output.secret(require_boolean(key))

    # @return [Integer, nil]
    def get_integer(key) = coerce(key, "integer") { |value| Integer(value, exception: false) }

    # @return [Integer]
    def require_integer(key) = required(key) { get_integer(key) }

    # @return [Output<Integer>, nil]
    def get_secret_integer(key) = as_secret(get_integer(key))

    # @return [Output<Integer>]
    def require_secret_integer(key) = Output.secret(require_integer(key))

    # @return [Float, nil]
    def get_float(key) = coerce(key, "float") { |value| Float(value, exception: false) }

    # @return [Float]
    def require_float(key) = required(key) { get_float(key) }

    # @return [Output<Float>, nil]
    def get_secret_float(key) = as_secret(get_float(key))

    # @return [Output<Float>]
    def require_secret_float(key) = Output.secret(require_float(key))

    # Reads a value that was set as structured data with `pulumi config set --path`.
    #
    # @return [Object, nil]
    def get_object(key)
      coerce(key, "JSON object") do |value|
        JSON.parse(value)
      rescue JSON::ParserError
        nil
      end
    end

    # @return [Object]
    def require_object(key) = required(key) { get_object(key) }

    # @return [Output, nil]
    def get_secret_object(key) = as_secret(get_object(key))

    # @return [Output]
    def require_secret_object(key) = Output.secret(require_object(key))

    # Whether this key was set with `pulumi config set --secret`.
    #
    # Reading such a value with {#get} returns it in the clear, matching the other SDKs --
    # marking it is {#get_secret}'s job. This lets a program check rather than assume.
    #
    # @return [Boolean]
    def secret?(key)
      Runtime.settings.config_secret_keys.include?(full_key(key))
    end

    private

    def full_key(key) = "#{namespace}:#{key}"

    def raw(key) = Runtime.settings.config[full_key(key)]

    # Reads a value and converts it, turning a failed conversion into a typed error.
    #
    # The block returns nil to mean "this is not a valid X", which is unambiguous because
    # an absent key short-circuits before the block runs.
    def coerce(key, description)
      value = raw(key)
      return nil if value.nil?

      converted = yield(value)
      raise ConfigTypeError.new(full_key(key), value, description) if converted.nil?

      converted
    end

    # Turns an absent value into ConfigMissingError.
    #
    # `false` is a legitimate value, so this checks for nil rather than truthiness -- an
    # `or raise` here would reject `pulumi config set flag false`.
    def required(key)
      value = yield
      raise ConfigMissingError, full_key(key) if value.nil?

      value
    end

    def as_secret(value) = value.nil? ? nil : Output.secret(value)
  end

  class << self
    # Configuration for the running stack.
    #
    # @param namespace [String, nil] defaults to the current project's name
    # @return [Config]
    def config(namespace = nil)
      Config.new(namespace)
    end
  end
end
