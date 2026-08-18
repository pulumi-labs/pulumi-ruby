// Copyright 2026, Pulumi Corporation.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package codegen

import (
	"github.com/pulumi/pulumi/pkg/v3/codegen/hcl2/model"
	"github.com/pulumi/pulumi/pkg/v3/codegen/pcl"
)

// genResource emits a resource declaration.
//
// Resources are constructed through Pulumi::CustomResource with their type token rather
// than a generated class, because SDK generation is not implemented yet. The shape is the
// same either way -- name, inputs, options -- so the programs this emits keep working
// unchanged once generated SDKs replace the token.
func (g *generator) genResource(r *pcl.Resource) {
	token, _ := r.GetToken()

	class := "Pulumi::CustomResource"
	if isComponentToken(r) {
		class = "Pulumi::ComponentResource"
	}

	// Definition.Labels[0] rather than the deprecated Name(): the two are the same, but
	// Name() is on its way out. LogicalName() is separate and must not be substituted --
	// it is what reaches RegisterResource, so changing it would rename the resource.
	variable := localName(r.Definition.Labels[0])

	g.writef("%s = %s.new(%s, %s, {", variable, class, quote(token), quote(r.LogicalName()))
	if len(r.Inputs) > 0 {
		g.indented(func() {
			for _, input := range r.Inputs {
				g.newline()
				// Provider property names go on the wire as written, so they are string keys
				// rather than symbols: PCL preserves the schema's casing and the SDK does not
				// translate it.
				g.writef("%s => ", quote(input.Name))
				g.genExpression(input.Value)
				g.writef(",")
			}
		})
		g.newline()
	}
	g.writef("}")

	if options := g.resourceOptions(r); options != "" {
		g.writef(", %s", options)
	}
	g.writef(")")
}

// isComponentToken reports whether a token names a component rather than a custom resource.
func isComponentToken(r *pcl.Resource) bool {
	return r.Schema != nil && r.Schema.IsComponent
}

// resourceOptions renders the ResourceOptions argument, or "" when there are none.
func (g *generator) resourceOptions(r *pcl.Resource) string {
	if r.Options == nil {
		return ""
	}

	// Rendered into a nested generator so that the caller can tell "no options" from
	// "options that all turned out to be empty" without emitting a stray argument.
	nested := &generator{indent: g.indent}
	var count int
	emit := func(name string, value model.Expression) {
		if value == nil {
			return
		}
		if count > 0 {
			nested.writef(", ")
		}
		nested.writef("%s: ", name)
		nested.genExpression(value)
		count++
	}

	emit("parent", r.Options.Parent)
	emit("provider", r.Options.Provider)
	emit("providers", r.Options.Providers)
	emit("depends_on", r.Options.DependsOn)
	emit("protect", r.Options.Protect)
	emit("retain_on_delete", r.Options.RetainOnDelete)
	emit("aliases", r.Options.Aliases)

	g.diagnostics = append(g.diagnostics, nested.diagnostics...)
	if count == 0 {
		return ""
	}
	return "Pulumi::ResourceOptions.new(" + nested.buf.String() + ")"
}
