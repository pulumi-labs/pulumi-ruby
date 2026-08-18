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

# `well_known_types` is what adds Struct.from_hash / Value#to_ruby and friends; the
# generated struct_pb only defines the raw message types. rpc.rb needs both -- it hand
# rolls the conversions that carry Pulumi semantics (unknowns, secrets, assets) but
# leans on these for the plain cases.
require "google/protobuf/well_known_types"

# The generated protobuf bindings live under runtime/proto and are namespaced
# `Pulumirpc` (protoc derives that from the `pulumirpc` package in the .proto files).
#
# Only the services the SDK itself speaks are required here. The rest of the generated
# tree -- language, converter, codegen, analyzer, events -- exists for the Go language
# host and other tooling, and loading it would cost every Pulumi program startup time
# for no benefit.
require_relative "proto/pulumi/resource_services_pb"
require_relative "proto/pulumi/engine_services_pb"
