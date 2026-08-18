# frozen_string_literal: true

module Pulumi
  module Spec
    # A mock monitor that counts feature-negotiation round trips, so specs can assert the
    # SDK negotiates once rather than once per resource.
    class CountingMonitor < Pulumi::Testing::MockMonitor
      attr_reader :deployment_info_calls, :supports_feature_calls

      def initialize(*, **)
        super
        @deployment_info_calls = Concurrent::AtomicFixnum.new(0)
        @supports_feature_calls = Concurrent::AtomicFixnum.new(0)
      end

      def get_deployment_info(request)
        @deployment_info_calls.increment
        # Widen the window between "is it computed?" and "store it", so an unguarded lazy
        # initializer reliably fails the spec rather than failing one run in fifty.
        sleep 0.01
        super
      end

      def supports_feature(request)
        @supports_feature_calls.increment
        super
      end
    end
  end
end
