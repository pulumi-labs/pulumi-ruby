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

// Package codegen turns Pulumi's language-neutral representations into Ruby: PCL programs
// into `main.rb` ("programgen"), and package schemas into SDK gems ("sdkgen").
package codegen

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/hashicorp/hcl/v2"
	"github.com/pulumi/pulumi/pkg/v3/codegen/hcl2/model"
	"github.com/pulumi/pulumi/pkg/v3/codegen/pcl"
	"github.com/pulumi/pulumi/sdk/v3/go/common/encoding"
	"github.com/pulumi/pulumi/sdk/v3/go/common/workspace"
)

// generator walks a bound PCL program and writes Ruby.
type generator struct {
	buf    bytes.Buffer
	indent int

	// diagnostics collects anything the generator could not translate. A diagnostic is
	// preferable to a panic or to silently emitting something that does not run: the
	// caller reports them and the user sees which construct is unsupported.
	diagnostics hcl.Diagnostics

	// needsConfig records whether the program read any configuration, so that the
	// `config = Pulumi.config` preamble is emitted only when it would be used -- an unused
	// local is exactly the sort of thing RuboCop complains about in generated code. The
	// same goes for the standard-library requires below.
	needsConfig bool
	needsDigest bool
}

// rubyNameInfo tells PCL's rewriters what a name looks like in Ruby, so that the
// parameters it introduces for apply lambdas are already snake_case.
type rubyNameInfo struct{}

func (rubyNameInfo) Format(name string) string { return localName(name) }

// GenerateProgram translates a bound PCL program into Ruby source files.
func GenerateProgram(program *pcl.Program) (map[string][]byte, hcl.Diagnostics, error) {
	g := &generator{}

	// Rewrite expressions that read an Output into explicit applies before generating.
	//
	// Without this the generator emits `secret_number + 1.25` literally, which raises
	// NoMethodError at runtime because Output has no #+ -- and deliberately so: an Output
	// has no value to add until the engine resolves it. RewriteApplies is what turns that
	// into `secret_number.apply { |n| n + 1.25 }`. Every language generator does this; it
	// is not a Ruby-specific concern.
	for _, node := range program.Nodes {
		if resource, ok := node.(*pcl.Resource); ok {
			for _, input := range resource.Inputs {
				rewritten, diagnostics := pcl.RewriteApplies(input.Value, rubyNameInfo{}, false)
				g.diagnostics = g.diagnostics.Extend(diagnostics)
				input.Value = rewritten
			}
			continue
		}

		expr := nodeExpression(node)
		if expr == nil {
			continue
		}
		rewritten, diagnostics := pcl.RewriteApplies(expr, rubyNameInfo{}, false)
		g.diagnostics = g.diagnostics.Extend(diagnostics)
		setNodeExpression(node, rewritten)
	}

	// The body is generated first so that the preamble knows what it needs to declare.
	body := g.genBody(program)

	var out bytes.Buffer
	out.WriteString("# frozen_string_literal: true\n\n")
	out.WriteString("require \"pulumi\"\n")
	if g.needsDigest {
		out.WriteString("require \"digest\"\n")
	}
	if g.needsConfig {
		out.WriteString("\nconfig = Pulumi.config\n")
	}
	if body != "" {
		out.WriteString("\n")
		out.WriteString(body)
	}

	return map[string][]byte{"main.rb": out.Bytes()}, g.diagnostics, nil
}

// nodeExpression returns the expression a node computes, or nil when it has none.
//
// PCL nodes keep their expression in different places, so apply-rewriting needs a way to
// get at it uniformly. A Resource is handled separately: its inputs are rewritten
// individually because each is its own expression.
func nodeExpression(node pcl.Node) model.Expression {
	switch node := node.(type) {
	case *pcl.ConfigVariable:
		return node.DefaultValue
	case *pcl.LocalVariable:
		return node.Definition.Value
	case *pcl.OutputVariable:
		return node.Value
	default:
		return nil
	}
}

func setNodeExpression(node pcl.Node, expr model.Expression) {
	if expr == nil {
		return
	}
	switch node := node.(type) {
	case *pcl.ConfigVariable:
		node.DefaultValue = expr
	case *pcl.LocalVariable:
		node.Definition.Value = expr
	case *pcl.OutputVariable:
		node.Value = expr
	}
}

func (g *generator) genBody(program *pcl.Program) string {
	var out bytes.Buffer
	for _, node := range program.Nodes {
		g.buf.Reset()
		g.genNode(node)
		if g.buf.Len() > 0 {
			if out.Len() > 0 {
				out.WriteString("\n")
			}
			out.WriteString(g.buf.String())
		}
	}
	return out.String()
}

func (g *generator) genNode(node pcl.Node) {
	switch node := node.(type) {
	case *pcl.ConfigVariable:
		g.genConfigVariable(node)
	case *pcl.LocalVariable:
		g.genLocalVariable(node)
	case *pcl.OutputVariable:
		g.genOutputVariable(node)
	case *pcl.Resource:
		g.genResource(node)
	default:
		g.unsupportedf(node.SyntaxNode().Range(), "%T is not supported yet", node)
	}
}

// genConfigVariable emits the typed Config accessor matching the declared type.
//
// The accessor is chosen from the declared type rather than always reading a string,
// because the stack records config as strings and a program that adds 1 to a `number`
// needs a Float back, not "3.5".
func (g *generator) genConfigVariable(v *pcl.ConfigVariable) {
	getter := configGetter(v.Type(), v.DefaultValue != nil || v.Nullable, v.Secret)

	g.writef("%s = config.%s(%q)", localName(v.Name()), getter, v.LogicalName())
	if v.DefaultValue != nil {
		// `||` rather than a nil check: a default only applies when the key is unset, and
		// Ruby's false is a legitimate config value, so booleans use an explicit form.
		if isBoolType(v.Type()) {
			g.writef("\n%s = %s unless %s.nil?",
				localName(v.Name()), localName(v.Name()), localName(v.Name()))
			g.buf.Reset()
			g.writef("%s = config.%s(%q)", localName(v.Name()), getter, v.LogicalName())
			g.writef("\n%s = ", localName(v.Name()))
			g.genExpression(v.DefaultValue)
			g.writef(" if %s.nil?", localName(v.Name()))
		} else {
			g.writef(" || ")
			g.genExpression(v.DefaultValue)
		}
	}
	g.needsConfig = true
}

func (g *generator) genLocalVariable(v *pcl.LocalVariable) {
	g.writef("%s = ", localName(v.Name()))
	g.genExpression(v.Definition.Value)
}

func (g *generator) genOutputVariable(v *pcl.OutputVariable) {
	// Parenthesized because `Pulumi.export "n", x.apply { ... }` binds the braces to apply
	// but a do/end block would bind to export. Parentheses remove the question, and
	// RuboCop's Lint/AmbiguousBlockAssociation flags the unparenthesized form.
	g.writef("Pulumi.export(%q, ", v.LogicalName())
	g.genExpression(v.Value)
	g.writef(")")
}

// configGetter picks the Config method for a declared PCL type.
func configGetter(t model.Type, optional, secret bool) string {
	name := "require"
	if optional {
		name = "get"
	}
	if secret {
		name += "_secret"
	}

	switch {
	case isBoolType(t):
		return name + "_boolean"
	case isIntType(t):
		return name + "_integer"
	case isNumberType(t):
		return name + "_float"
	case isStringType(t):
		return name
	default:
		// Lists, maps and objects are all recorded as JSON by `pulumi config set --path`.
		return name + "_object"
	}
}

func isBoolType(t model.Type) bool   { return unwrapType(t) == model.BoolType }
func isIntType(t model.Type) bool    { return unwrapType(t) == model.IntType }
func isNumberType(t model.Type) bool { return unwrapType(t) == model.NumberType }
func isStringType(t model.Type) bool { return unwrapType(t) == model.StringType }

// unwrapType strips the Output/Promise/optional wrappers a bound type may carry, so that
// the underlying primitive is what drives the decision.
func unwrapType(t model.Type) model.Type {
	for {
		switch inner := t.(type) {
		case *model.OutputType:
			t = inner.ElementType
		case *model.PromiseType:
			t = inner.ElementType
		case *model.UnionType:
			// An optional is modelled as a union with none; the primitive is what matters.
			var only model.Type
			for _, element := range inner.ElementTypes {
				if element == model.NoneType {
					continue
				}
				if only != nil {
					return t
				}
				only = element
			}
			if only == nil {
				return t
			}
			t = only
		default:
			return t
		}
	}
}

func (g *generator) writef(format string, args ...any) {
	fmt.Fprintf(&g.buf, format, args...)
}

func (g *generator) indented(f func()) {
	g.indent += 2
	f()
	g.indent -= 2
}

func (g *generator) newline() {
	g.writef("\n%s", strings.Repeat(" ", g.indent))
}

func (g *generator) unsupportedf(subject hcl.Range, format string, args ...any) {
	g.diagnostics = append(g.diagnostics, &hcl.Diagnostic{
		Severity: hcl.DiagError,
		Summary:  "unsupported in Ruby",
		Detail:   fmt.Sprintf(format, args...),
		Subject:  &subject,
	})
}

// GenerateProject writes a complete, runnable Ruby project for a PCL program.
func GenerateProject(
	targetDirectory string, project workspace.Project, program *pcl.Program,
	localDependencies map[string]string,
) error {
	files, diagnostics, err := GenerateProgram(program)
	if err != nil {
		return err
	}
	if diagnostics.HasErrors() {
		return diagnostics
	}

	// A Gemfile is what makes the directory runnable: the language host resolves the SDK
	// through Bundler, and `pulumi install` runs `bundle install` against this file.
	files["Gemfile"] = []byte(gemfile(localDependencies))

	project.Runtime = workspace.NewProjectRuntimeInfo("ruby", nil)
	projectYAML, err := encoding.YAML.Marshal(project)
	if err != nil {
		return fmt.Errorf("marshaling Pulumi.yaml: %w", err)
	}
	files["Pulumi.yaml"] = projectYAML

	for name, contents := range files {
		path := filepath.Join(targetDirectory, name)
		if err := os.MkdirAll(filepath.Dir(path), 0o750); err != nil {
			return fmt.Errorf("creating %s: %w", filepath.Dir(path), err)
		}
		if err := os.WriteFile(path, contents, 0o600); err != nil {
			return fmt.Errorf("writing %s: %w", path, err)
		}
	}
	return nil
}

// gemfile renders the project's Gemfile.
//
// A local dependency is written as a `path:` source, which is how the conformance harness
// points a generated project at the SDK it just packed, and how a developer points one at
// a checkout.
func gemfile(localDependencies map[string]string) string {
	var out strings.Builder
	out.WriteString("# frozen_string_literal: true\n\nsource \"https://rubygems.org\"\n\n")

	names := make([]string, 0, len(localDependencies))
	for name := range localDependencies {
		names = append(names, name)
	}
	sort.Strings(names)

	if len(names) == 0 {
		out.WriteString("gem \"pulumi\"\n")
		return out.String()
	}

	for _, name := range names {
		gem := name
		if gem != "pulumi" {
			gem = "pulumi-" + strings.TrimPrefix(gem, "pulumi-")
		}
		fmt.Fprintf(&out, "gem %q, path: %q\n", gem, localDependencies[name])
	}
	return out.String()
}
