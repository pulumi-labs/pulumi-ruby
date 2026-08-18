# frozen_string_literal: true

module Pulumi
  module Spec
    # Captures the raw RegisterResourceRequest protos the SDK sends.
    #
    # Testing::Result reports the deserialized view, which is the right level for most
    # assertions but hides the request fields entirely -- which is how options that were
    # accepted and never transmitted went unnoticed. These specs assert on the wire.
    module RecordingMonitor
      class << self
        attr_accessor :last_requests
      end

      def register_resource(request)
        RecordingMonitor.last_requests << request
        super
      end
    end
  end
end

# Prepended rather than subclassed so that Testing.run, which constructs the monitor
# itself, records without needing to know about this at all.
Pulumi::Testing::MockMonitor.prepend(Pulumi::Spec::RecordingMonitor)

RSpec.configure do |config|
  config.before { Pulumi::Spec::RecordingMonitor.last_requests = [] }
end
