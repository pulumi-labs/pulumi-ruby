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
	"bytes"
	"fmt"
	"strings"

	"github.com/pulumi/pulumi/pkg/v3/codegen/schema"
)

// genResource emits the class for one resource, and returns its path within lib/.
//
// The generated class declares its input properties, which is what turns a misspelled
// property into an ArgumentError at the call rather than something the provider rejects
// much later -- the strongest answer available to "Ruby has no type checking".
func (g *packageGenerator) genResource(r *schema.Resource) (string, []byte, error) {
	relative, namespace := g.resourcePath(r.Token)
	_, className := splitToken(r.Token)
	className = pascalCase(className)

	var out bytes.Buffer
	writeHeader(&out, g.tool)
	out.WriteString("require \"pulumi\"\n\n")

	indent := ""
	for _, module := range namespace {
		fmt.Fprintf(&out, "%smodule %s\n", indent, module)
		indent += "  "
	}

	g.genArgsClass(&out, indent, className, r.InputProperties)
	out.WriteString("\n")
	g.genResourceClass(&out, indent, className, r)

	for range namespace {
		indent = strings.TrimSuffix(indent, "  ")
		fmt.Fprintf(&out, "%send\n", indent)
	}

	return relative, out.Bytes(), nil
}

func (g *packageGenerator) genArgsClass(
	out *bytes.Buffer, indent, className string, properties []*schema.Property,
) {
	fmt.Fprintf(out, "%s# The inputs to a {%s}.\n", indent, className)
	fmt.Fprintf(out, "%sclass %sArgs < ::Pulumi::Args\n", indent, className)
	for _, property := range sortedProperties(properties) {
		ruby := localName(property.Name)
		if ruby == property.Name {
			fmt.Fprintf(out, "%s  property :%s\n", indent, ruby)
		} else {
			fmt.Fprintf(out, "%s  property :%s, wire: :%s\n", indent, ruby, property.Name)
		}
	}
	fmt.Fprintf(out, "%send\n", indent)
}

func (g *packageGenerator) genResourceClass(
	out *bytes.Buffer, indent, className string, r *schema.Resource,
) {
	if description := firstLine(r.Comment, ""); description != "" {
		fmt.Fprintf(out, "%s# %s\n", indent, description)
	}

	base := "::Pulumi::CustomResource"
	if r.IsComponent {
		base = "::Pulumi::ComponentResource"
	}
	if r.IsProvider {
		base = "::Pulumi::ProviderResource"
	}

	fmt.Fprintf(out, "%sclass %s < %s\n", indent, className, base)
	fmt.Fprintf(out, "%s  TYPE = %q\n\n", indent, r.Token)

	inputs := sortedProperties(r.InputProperties)

	// Explicit keyword arguments rather than **kwargs: Ruby then reports an unknown
	// keyword at the call site for free, which is the whole point of generating this.
	fmt.Fprintf(out, "%s  def initialize(name, ", indent)
	for _, property := range inputs {
		fmt.Fprintf(out, "%s: nil, ", localName(property.Name))
	}
	fmt.Fprintf(out, "opts: nil, &block)\n")

	fmt.Fprintf(out, "%s    args = %sArgs.build({\n", indent, className)
	for _, property := range inputs {
		ruby := localName(property.Name)
		fmt.Fprintf(out, "%s      %s: %s,\n", indent, ruby, ruby)
	}
	// An unset keyword must be absent rather than sent as null, or a provider cannot tell
	// "leave this alone" from "set it to nothing".
	fmt.Fprintf(out, "%s    }.compact, &block)\n\n", indent)

	if r.IsProvider {
		fmt.Fprintf(out, "%s    super(%q, name, args.to_h, opts)\n", indent, g.pkg.Name)
	} else {
		fmt.Fprintf(out, "%s    super(TYPE, name, args.to_h, opts)\n", indent)
	}
	fmt.Fprintf(out, "%s  end\n", indent)

	for _, property := range sortedProperties(r.Properties) {
		ruby := localName(property.Name)
		fmt.Fprintf(out, "\n%s  # @return [::Pulumi::Output]\n", indent)
		fmt.Fprintf(out, "%s  def %s\n%s    output(%q)\n%s  end\n", indent, ruby, indent, property.Name, indent)
	}

	fmt.Fprintf(out, "%send\n", indent)
}

// sortedProperties returns properties in a stable order.
//
// Schema order is not guaranteed stable across loads, and the generated output is snapshot
// compared byte for byte, so an unstable order would produce spurious diffs.
func sortedProperties(properties []*schema.Property) []*schema.Property {
	sorted := make([]*schema.Property, len(properties))
	copy(sorted, properties)
	for i := 1; i < len(sorted); i++ {
		for j := i; j > 0 && sorted[j].Name < sorted[j-1].Name; j-- {
			sorted[j], sorted[j-1] = sorted[j-1], sorted[j]
		}
	}
	return sorted
}
