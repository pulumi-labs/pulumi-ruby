# frozen_string_literal: true

module Pulumi
  module Spec
    # Stands in for a provider: echoes a resource's inputs back and adds a computed
    # property, so specs can check that values really make the round trip through
    # serialization, the monitor, and deserialization.
    class EchoMocks < Pulumi::Testing::Mocks
      def new_resource(args)
        ["#{args.name}-id", args.inputs.merge("arn" => "arn:fake:#{args.name}")]
      end
    end
  end
end
