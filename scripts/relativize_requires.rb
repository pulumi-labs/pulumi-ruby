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

# grpc_tools_ruby_protoc emits `require 'pulumi/resource_pb'`, which resolves only if the
# generated tree is on $LOAD_PATH. That is unworkable here for two reasons: the gem's
# require path is `lib`, so `pulumi/resource_pb` would collide with the SDK's own
# `lib/pulumi/` namespace; and a library that mutates the global $LOAD_PATH can shadow
# unrelated gems.
#
# So: rewrite each intra-tree require to a require_relative. Requires that point outside
# the generated tree (google/protobuf/struct_pb, grpc, ...) come from real gems and are
# left alone. Membership is decided by what was actually generated rather than by a
# hardcoded prefix, so this keeps working if the proto layout changes.

require "pathname"

root = Pathname.new(ARGV.fetch(0)).expand_path
raise ArgumentError, "not a directory: #{root}" unless root.directory?

files = root.glob("**/*.rb")
generated = files.to_h { |f| [f.relative_path_from(root).sub_ext("").to_s, f] }

rewritten = 0
files.each do |file|
  dir = file.dirname
  source = file.read

  updated = source.gsub(/^require (?<q>['"])(?<path>[^'"]+)\k<q>$/) do
    target = generated[Regexp.last_match[:path]]
    next Regexp.last_match(0) if target.nil?

    "require_relative #{target.relative_path_from(dir).sub_ext('').to_s.inspect}"
  end

  next if updated == source

  file.write(updated)
  rewritten += 1
end

puts "    rewrote requires in #{rewritten} of #{files.size} files"
