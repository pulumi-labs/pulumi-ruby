# frozen_string_literal: true

module Pulumi
  module Spec
    # A provider that returns a secret property, the way a database provider returns a
    # generated password. During a preview the engine sends secret(unknown) for it, which
    # is the shape that used to deserialize as *known*.
    class SecretMocks < Pulumi::Testing::Mocks
      def new_resource(args)
        ["#{args.name}-id", args.inputs.merge("password" => Pulumi::Output.secret("hunter2"))]
      end
    end
  end
end
