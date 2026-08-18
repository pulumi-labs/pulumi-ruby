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

require_relative "output"

module Pulumi
  # Options controlling how a provider function is invoked.
  class InvokeOptions
    attr_accessor :provider, :version, :plugin_download_url, :parent, :depends_on

    def initialize(provider: nil, version: nil, plugin_download_url: nil, parent: nil, depends_on: nil)
      @provider = provider
      @version = version
      @plugin_download_url = plugin_download_url
      @parent = parent
      @depends_on = depends_on
    end
  end

  class << self
    # Calls a provider function -- one that reads rather than creates, like looking up an
    # AMI or the current account id.
    #
    #   region = Pulumi.invoke("aws:index/getRegion:getRegion", {})
    #   Pulumi.export "region", region.apply { |r| r["name"] }
    #
    # The result is an {Output} rather than a plain value, for two reasons: the call has to
    # cross a process boundary, and its arguments may themselves depend on resources that
    # do not exist yet. In that case -- during a preview -- the engine returns unknown
    # instead of calling the provider at all.
    #
    # @param token [String] the function token, e.g. "aws:index/getRegion:getRegion"
    # @param args [Hash] the function's arguments
    # @param opts [InvokeOptions, nil]
    # @return [Output<Hash>]
    def invoke(token, args = {}, opts = nil)
      Runtime.invoke(token, args, opts || InvokeOptions.new)
    end
  end
end
