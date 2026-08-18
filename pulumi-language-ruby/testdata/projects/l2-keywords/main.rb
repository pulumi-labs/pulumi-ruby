# frozen_string_literal: true

require "pulumi"
require "pulumi/keywords"

first_resource = ::Pulumi::Keywords::SomeResource.new("firstResource",
  builtins: "builtins",
  lambda: "lambda",
  property: "property")
second_resource = ::Pulumi::Keywords::SomeResource.new("secondResource",
  builtins: first_resource["builtins"],
  lambda: first_resource["lambda"],
  property: first_resource["property"])
lambda_module_resource = ::Pulumi::Keywords::Lambda::SomeResource.new("lambdaModuleResource",
  builtins: "builtins",
  lambda: "lambda",
  property: "property")
lambda_resource = ::Pulumi::Keywords::Module::Lambda.new("lambdaResource",
  builtins: "builtins",
  lambda: "lambda",
  property: "property")