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

module Pulumi
  # Runs a configuration block against an {Args} object while keeping the caller's scope
  # reachable.
  #
  # This is what makes the Chef-flavoured form work:
  #
  #   Bucket.new("assets") do
  #     acl "private"
  #     tags "Env" => env      # `env` is a local in the *calling* scope
  #   end
  #
  # A bare `instance_eval` would break that. `self` inside the block becomes the target,
  # so instance variables silently resolve to nil against the new self and calls to the
  # caller's own methods raise NameError. Both are among the sharper edges Chef cookbooks
  # were full of. This proxy restores them: the caller's instance variables are copied in,
  # and anything the target does not answer is forwarded to the object the block was
  # written in.
  #
  # It inherits from Object with almost everything undefined rather than from BasicObject,
  # because a property can legitimately be named `hash`, `method`, `display` or `class`,
  # and inherited methods would swallow those calls before method_missing ever saw them.
  # (Verified: a naive Object-derived proxy answers `hash "abc"` with
  # `ArgumentError: wrong number of arguments (given 1, expected 0)`.)
  #
  # @api private
  class DSLProxy
    KEPT_METHODS = %i[
      __send__ __id__ object_id equal? instance_variable_get instance_variable_set
      instance_variables method_missing respond_to_missing?
    ].freeze

    (instance_methods - KEPT_METHODS).each { |method| undef_method(method) }

    def initialize(target, fallback)
      @__target = target
      @__fallback = fallback

      # Copy the caller's instance variables in so `@foo` reads work. They are copied back
      # out afterwards so a block that assigns one is not silently ignored.
      __copy_ivars(from: fallback, to: self)
    end

    # Runs the block against this proxy, then returns the target.
    #
    # instance_exec is fetched from BasicObject and bound rather than called directly,
    # because the blanket undef_method above removes it from this class along with
    # everything else. Calling it as a plain method would fall into method_missing, get
    # forwarded to the target, and run the block against the target itself -- silently
    # bypassing the proxy and losing the caller's scope, which is the entire point.
    # Fetching it this way also keeps `instance_exec` usable as a property name.
    INSTANCE_EXEC = ::BasicObject.instance_method(:instance_exec)

    def __run(block)
      INSTANCE_EXEC.bind(self).call(&block)
      __copy_ivars(from: self, to: @__fallback)
      @__target
    end

    def method_missing(name, ...)
      target = instance_variable_get(:@__target)

      # Dispatch on whether the target *really defines* the method, not on respond_to?.
      # An open args bag answers respond_to? for everything, so using it here would send
      # every name to the bag and the caller's own methods would silently come back nil.
      return target.__send__(name, ...) if __defined_on?(target, name)

      fallback = instance_variable_get(:@__fallback)
      return fallback.__send__(name, ...) if fallback.respond_to?(name, true)

      # Neither side defines it. Hand it to the target anyway: an open bag treats it as a
      # new property, and a bag with declared properties raises NoMethodError naming
      # itself, which is the more useful of the two messages.
      target.__send__(name, ...)
    end

    # Nothing normally reaches this: `respond_to?` is undef'd above along with everything
    # else, so a `respond_to?` written inside a block goes through method_missing to the
    # target or the caller instead. It is kept so the object does not lie to anything that
    # gets at Object#respond_to? another way, such as a bound UnboundMethod.
    def respond_to_missing?(name, include_private = false)
      instance_variable_get(:@__target).respond_to?(name) ||
        instance_variable_get(:@__fallback).respond_to?(name, include_private)
    end

    private

    # Whether an object defines a method for real, as opposed to answering it through
    # method_missing.
    #
    # Checking the singleton class covers both singleton methods and everything inherited
    # from the object's class.
    #
    # Like the other helpers here it is __-prefixed, because any plain name defined on
    # this class would shadow a resource property called the same thing.
    def __defined_on?(object, name)
      singleton = object.singleton_class
      singleton.method_defined?(name) || singleton.private_method_defined?(name)
    end

    def __copy_ivars(from:, to:)
      from.instance_variables.each do |ivar|
        next if ivar.to_s.start_with?("@__")

        to.instance_variable_set(ivar, from.instance_variable_get(ivar))
      end
    end
  end
end
