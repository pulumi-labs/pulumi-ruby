# frozen_string_literal: true

require "pulumi"
require "pulumi/simple"

target = ::Pulumi::Simple::Resource.new("target",
  value: true)
deleted_with = ::Pulumi::Simple::Resource.new("deletedWith",
  value: true)
not_deleted_with = ::Pulumi::Simple::Resource.new("notDeletedWith",
  value: true)