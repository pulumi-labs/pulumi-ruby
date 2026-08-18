# frozen_string_literal: true

# A sample Pulumi program, type-checked against sig/ by `rake steep`.
#
# The signatures exist so that *user programs* can be checked -- which is the answer to the
# most common objection to Ruby for infrastructure, that there is no equivalent to what
# TypeScript gives. So the thing worth proving in CI is that a realistic program checks
# cleanly, not that the SDK's own internals do.
#
# This file is not shipped in the gem and is never executed.

require "pulumi"

class Website < Pulumi::ComponentResource
  attr_reader :endpoint

  def initialize(name, index_html:, opts: nil)
    super("example:web:Website", name, {}, opts)
    child = Pulumi::ResourceOptions.new(parent: self)

    bucket = Pulumi::CustomResource.new(
      "aws:s3/bucket:Bucket", "#{name}-bucket", { website: { indexDocument: "index.html" } }, child
    )

    Pulumi::CustomResource.new(
      "aws:s3/bucketObject:BucketObject", "#{name}-index",
      { bucket: bucket.id, key: "index.html", source: Pulumi::StringAsset.new(index_html) },
      child
    )

    @endpoint = bucket.output("websiteEndpoint")
    register_outputs(endpoint: @endpoint)
  end
end

config = Pulumi.config
# @type var replicas: Integer
replicas = config.get_integer("replicas") || 1
token = config.require_secret("apiToken")

site = Website.new("site", index_html: "<h1>hello</h1>")

network = Pulumi::StackReference.new("acme/network/prod")
subnet = network.require_output("subnetId")

Pulumi.export("url", site.endpoint.apply { |endpoint| "https://#{endpoint}" })
Pulumi.export "combined", Pulumi::Output.all(site.endpoint, subnet)
Pulumi.export "formatted", Pulumi::Output.format("https://%s (%d replicas)", site.endpoint, replicas)
Pulumi.export "token", token

Pulumi::Log.info("deployed #{Pulumi.project}/#{Pulumi.stack}")
