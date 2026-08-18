# frozen_string_literal: true

module Pulumi
  module Spec
    # The magic signatures Pulumi's wire format uses, restated as literals.
    #
    # These are deliberately *not* referenced from lib/: asserting the implementation
    # against its own constants would pass even if a signature were mistyped. They are
    # copied from pulumi/pulumi's sdk/go/common/resource/sig/sig.go, which is canonical
    # for every SDK.
    module WireFormat
      SIG_KEY = "4dabf18193072939515e22adb298388d"

      ASSET              = "c44067f5952c0a294b673a41bacd8c17"
      ARCHIVE            = "0def7320c3a5731c473e5ecbe6d01bc7"
      SECRET             = "1b47061264138c4ac30d75fd1eb44270"
      RESOURCE_REFERENCE = "5cf8f73096256a8f31e491e813e4eb8e"
      OUTPUT_VALUE       = "d0e6a833031e9bbcd3f4e8bde6ca49a4"
      BYTE_STRING        = "803fd3297a5875dc03ca845dda5d2a98"

      UNKNOWN = "04da6b54-80e4-46f7-96ec-b56ff0331ba9"
    end

    # A stand-in for a resource.
    #
    # The serializer identifies resources structurally -- anything answering #urn and
    # #custom? -- so that resource.rb can depend on rpc.rb rather than the reverse. This
    # class is the executable statement of that contract; if the serializer ever starts
    # requiring more of a resource, this is what will fail.
    class FakeResource
      attr_reader :urn, :id

      def initialize(urn:, id: nil, custom: true)
        @urn = Pulumi::Output.from(urn)
        @id = id.nil? ? nil : Pulumi::Output.from(id)
        @custom = custom
      end

      def custom?
        @custom
      end
    end
  end
end
