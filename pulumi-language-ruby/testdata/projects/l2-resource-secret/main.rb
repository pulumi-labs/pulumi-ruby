# frozen_string_literal: true

require "pulumi"
require "pulumi/secret"

res = ::Pulumi::Secret::Resource.new("res",
  private: "closed",
  public: "open",
  private_data: {
    "private" => "closed",
    "public" => "open",
  },
  public_data: {
    "private" => "closed",
    "public" => "open",
  },
  private_array: [
    "closed",
  ],
  private_map: {
    "key" => "closed",
  },
  private_data_array: [
    {
      "private" => "closed",
      "public" => "open",
    },
  ],
  private_data_map: {
    "key" => {
      "private" => "closed",
      "public" => "open",
    },
  })