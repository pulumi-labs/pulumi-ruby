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
  # Base class for every error the Pulumi SDK raises.
  class Error < StandardError; end

  # Raised for a problem the user can act on. The engine prints the message on its own
  # and suppresses the usual "program exited with non-zero exit code" wrapper, so the
  # message must stand alone.
  class RunError < Error; end

  # Raised when a program tries to use an {Output} where a plain value is required.
  #
  # Ruby's implicit conversion protocol is deliberately *not* implemented on Output (no
  # #to_str, #to_ary, #to_hash, #to_proc, #to_int), because answering those produces
  # errors like "can't convert Output to String (Output#to_str gives Output)" which tell
  # the user nothing. Leaving them undefined gets Ruby's own clear "no implicit
  # conversion of Pulumi::Output into String" instead. This error covers the cases we
  # *can* intercept usefully.
  class OutputToStringError < Error
    # Single-quoted heredoc: the sample code below contains #{...} that must survive
    # verbatim into the message rather than being interpolated here.
    MESSAGE = <<~'MESSAGE'
      Calling `to_s` on a Pulumi::Output is not supported.

      An Output's value is not known until the engine has talked to the provider, so it
      cannot be turned into a String while the program is still running. To build a
      string from one, stay inside the Output:

        # Interpolate:
        Pulumi::Output.format("https://%s/%s", bucket.website_endpoint, key)

        # Or compute with a block:
        bucket.website_endpoint.apply { |endpoint| "https://#{endpoint}" }

      See https://www.pulumi.com/docs/concepts/inputs-outputs for more details.
    MESSAGE

    def initialize
      super(MESSAGE)
    end
  end
end
