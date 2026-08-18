# frozen_string_literal: true

require "pulumi"
require "pulumi/config"

prov = ::Pulumi::Config::Providers::Config.new("prov",
  name: "my config",
  plugin_download_url: "not the same as the pulumi resource option")
res = ::Pulumi::Config::Resource.new("res",
  text: prov["version"])
Pulumi.export("pluginDownloadURL", prov["pluginDownloadURL"])