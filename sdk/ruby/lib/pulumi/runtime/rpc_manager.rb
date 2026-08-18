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

module Pulumi
  module Runtime
    # Tracks the RPCs a program has started but not yet finished.
    #
    # Registering a resource is fire-and-forget from the program's point of view: the
    # constructor returns immediately with Outputs that resolve later. That means a Ruby
    # program can reach its last line while registrations are still in flight, so the
    # entry point has to wait for them before exiting -- otherwise the engine sees the
    # program end and tears down the deployment mid-flight.
    #
    # A registration can also *fail*, and the first failure is what the user needs to see;
    # later ones are usually consequences of it. So the first error is kept and re-raised
    # after the drain rather than being lost in whichever thread happened to raise it.
    class RPCManager
      def initialize
        @mutex = Mutex.new
        @pending = []
        @error = nil
      end

      # Records an in-flight RPC. Its failure is the program's failure.
      #
      # @param future [Concurrent::Promises::Future]
      # @return [Concurrent::Promises::Future] the same future, for chaining
      def track(future)
        add(future, attribute_errors: true)
      end

      # Records work that must finish before the program exits, but whose failure is not
      # by itself a program failure.
      #
      # `Output#apply` blocks land here. They must be waited on, because a block can
      # declare a resource -- and if the drain concluded first, that resource would never
      # be registered and the engine would delete it on the next update. But their errors
      # are not attributed: a failure that is recovered by `rescue_apply`, or that belongs
      # to a value nothing ever consumed, should not fail the deployment. A failure that
      # *does* matter surfaces when the value is serialized into a resource's inputs, and
      # that registration is tracked with attribution.
      #
      # @return [Concurrent::Promises::Future] the same future, for chaining
      def track_side_effects(future)
        add(future, attribute_errors: false)
      end

      # Records the first error seen. Later errors are dropped, since they are usually
      # downstream of the first.
      def record_error(error)
        @mutex.synchronize { @error = error if @error.nil? }
      end

      # @return [Exception, nil] the first error recorded, if any
      def error
        @mutex.synchronize { @error }
      end

      # Waits for every tracked RPC to finish.
      #
      # Draining is a loop rather than a single pass because settling one registration can
      # start others -- a resource constructed inside an apply, for instance -- and those
      # must be waited on too.
      def drain
        loop do
          batch = @mutex.synchronize do
            pending = @pending
            @pending = []
            pending
          end
          break if batch.empty?

          batch.each do |entry|
            entry.future.wait
            record_error(entry.future.reason) if entry.attribute_errors && entry.future.rejected?
          end
        end
      end

      # A future to wait for, and whether its failure is the program's failure.
      Entry = ::Data.define(:future, :attribute_errors)

      private

      def add(future, attribute_errors:)
        @mutex.synchronize { @pending << Entry.new(future: future, attribute_errors: attribute_errors) }
        future
      end
    end
  end
end
