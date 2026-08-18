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
	"strings"

	"github.com/pulumi/pulumi/pkg/v3/codegen/hcl2/model"
	"github.com/pulumi/pulumi/pkg/v3/codegen/pcl"
	"github.com/pulumi/pulumi/pkg/v3/codegen/schema"
)

// genResource emits a resource declaration.
//
// A resource bound to a schema goes through its generated class; one without a schema
// falls back to a type token. Both produce the same registration -- the difference is
// whether the program gets declared properties and a name a reader recognises.
func (g *generator) genResource(r *pcl.Resource) {
	// Definition.Labels[0] rather than the deprecated Name(): the two are the same, but
	// Name() is on its way out. LogicalName() is separate and must not be substituted --
	// it is what reaches RegisterResource, so changing it would rename the resource.
	variable := localName(r.Definition.Labels[0])

	if r.Schema != nil {
		g.genGeneratedResource(variable, r)
		return
	}
	g.genTokenResource(variable, r)
}

// genGeneratedResource emits a resource through its generated class.
//
// This is the form a user writes: a named class taking keyword arguments, so a misspelled
// property is an ArgumentError at the call rather than something the provider rejects much
// later. The class carries its own type token, which is why none appears here.
func (g *generator) genGeneratedResource(variable string, r *pcl.Resource) {
	class, packageName := rubyResourceClass(r.Schema)
	g.requiredPackages[packageName] = struct{}{}

	g.writef("%s = %s.new(%s", variable, class, quote(r.LogicalName()))
	g.indented(func() {
		for _, input := range r.Inputs {
			g.writef(",")
			g.newline()
			// The generated class takes Ruby names; translating to the wire name is its
			// business, not the program's.
			g.writef("%s: ", localName(input.Name))
			g.genExpression(input.Value)
		}
		if options := g.resourceOptions(r); options != "" {
			g.writef(",")
			g.newline()
			g.writef("opts: %s", options)
		}
	})
	g.writef(")")
}

// genTokenResource emits a resource whose schema is unknown, using its type token.
//
// This is what a program gets without a generated SDK: it works against any provider, but
// gives up declared properties, so it is the fallback rather than the goal.
func (g *generator) genTokenResource(variable string, r *pcl.Resource) {
	token, _ := r.GetToken()

	class := "Pulumi::CustomResource"
	if isComponentToken(r) {
		class = "Pulumi::ComponentResource"
	}

	g.writef("%s = %s.new(%s, %s, {", variable, class, quote(token), quote(r.LogicalName()))
	if len(r.Inputs) > 0 {
		g.indented(func() {
			for _, input := range r.Inputs {
				g.newline()
				// Provider property names go on the wire as written, so they are string keys
				// rather than symbols: PCL preserves the schema's casing.
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

// rubyResourceClass maps a schema resource onto its generated Ruby class, and reports the
// package whose gem has to be required.
func rubyResourceClass(r *schema.Resource) (class, packageName string) {
	packageName = r.PackageReference.Name()

	module, name := splitToken(r.Token)
	parts := []string{"", "Pulumi", pascalCase(packageName)}
	if module != "" && module != "index" {
		for _, segment := range strings.Split(module, "/") {
			parts = append(parts, pascalCase(segment))
		}
	}
	parts = append(parts, pascalCase(name))

	return strings.Join(parts, "::"), packageName
}
