# frozen_string_literal: true

require "pulumi"

Pulumi.export("stackOutput", Pulumi.stack)
Pulumi.export("projectOutput", Pulumi.project)
Pulumi.export("organizationOutput", Pulumi.organization)