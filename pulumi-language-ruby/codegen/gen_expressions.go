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
	"fmt"
	"math"
	"math/big"
	"strconv"
	"strings"

	"github.com/hashicorp/hcl/v2"

	"github.com/pulumi/pulumi/pkg/v3/codegen/hcl2/model"
	"github.com/zclconf/go-cty/cty"
)

func (g *generator) genExpression(expr model.Expression) {
	switch expr := expr.(type) {
	case *model.LiteralValueExpression:
		g.genLiteral(expr)
	case *model.TemplateExpression:
		g.genTemplate(expr)
	case *model.TupleConsExpression:
		g.genTuple(expr)
	case *model.ObjectConsExpression:
		g.genObject(expr)
	case *model.ScopeTraversalExpression:
		g.genScopeTraversal(expr)
	case *model.RelativeTraversalExpression:
		g.genRelativeTraversal(expr)
	case *model.IndexExpression:
		g.genIndex(expr)
	case *model.BinaryOpExpression:
		g.genBinaryOp(expr)
	case *model.UnaryOpExpression:
		g.genUnaryOp(expr)
	case *model.ConditionalExpression:
		g.genConditional(expr)
	case *model.FunctionCallExpression:
		g.genFunctionCall(expr)
	case *model.AnonymousFunctionExpression:
		g.genAnonymousFunction(expr)
	default:
		g.unsupportedf(expr.SyntaxNode().Range(), "the expression %T is not supported yet", expr)
		g.writef("nil")
	}
}

func (g *generator) genLiteral(expr *model.LiteralValueExpression) {
	value := expr.Value
	switch {
	case value.IsNull():
		g.writef("nil")
	case value.Type() == cty.Bool:
		g.writef("%t", value.True())
	case value.Type() == cty.Number:
		g.writef("%s", formatNumber(value.AsBigFloat()))
	case value.Type() == cty.String:
		g.writef("%s", quote(value.AsString()))
	default:
		g.unsupportedf(expr.SyntaxNode().Range(), "the literal type %v is not supported", value.Type())
		g.writef("nil")
	}
}

// formatNumber renders a PCL number as a Ruby numeric literal.
//
// A value that is exactly an integer is written without a decimal point, so `0` stays `0`
// rather than becoming `0.0`: the conformance suite asserts on the resulting property
// types, and a stack output of 0.0 is not the same as 0. Anything else is written with
// enough precision to round-trip, which matters for the suite's float64 extremes.
func formatNumber(value *big.Float) string {
	if value.IsInt() {
		if i, accuracy := value.Int64(); accuracy == big.Exact {
			return strconv.FormatInt(i, 10)
		}
	}

	f, _ := value.Float64()
	if math.IsInf(f, 0) {
		// Ruby has no infinity literal; this is how it is spelled.
		if math.IsInf(f, 1) {
			return "Float::INFINITY"
		}
		return "-Float::INFINITY"
	}
	return strconv.FormatFloat(f, 'g', -1, 64)
}

// quote renders a Ruby string literal.
//
// Double quotes with explicit escapes, rather than single quotes, because the values here
// routinely contain characters that need escaping -- the conformance suite deliberately
// includes tabs, escapes, bells, nulls and astral-plane characters -- and a double-quoted
// literal is the only Ruby form that can express all of them.
func quote(s string) string {
	var out strings.Builder
	out.WriteByte('"')
	for _, r := range s {
		switch r {
		case '"':
			out.WriteString(`\"`)
		case '\\':
			out.WriteString(`\\`)
		case '\n':
			out.WriteString(`\n`)
		case '\r':
			out.WriteString(`\r`)
		case '\t':
			out.WriteString(`\t`)
		case '#':
			// Escaped so that a literal `#{` cannot start an interpolation.
			out.WriteString(`\#`)
		default:
			if r < 0x20 || r == 0x7f {
				fmt.Fprintf(&out, `\u{%x}`, r)
				continue
			}
			out.WriteRune(r)
		}
	}
	out.WriteByte('"')
	return out.String()
}

// genTemplate emits a string built from literal parts and interpolations.
//
// When every part is a literal the result is a plain string. Otherwise the parts may
// include Outputs, which cannot be interpolated -- `"#{output}"` cannot produce a value --
// so Output.format is used, with the interpolated parts as arguments.
func (g *generator) genTemplate(expr *model.TemplateExpression) {
	if literal, ok := templateLiteral(expr); ok {
		g.writef("%s", quote(literal))
		return
	}

	var format strings.Builder
	var args []model.Expression
	for _, part := range expr.Parts {
		if literal, ok := part.(*model.LiteralValueExpression); ok && literal.Value.Type() == cty.String {
			// %% is how a literal percent survives Kernel#format.
			format.WriteString(strings.ReplaceAll(literal.Value.AsString(), "%", "%%"))
			continue
		}
		format.WriteString("%s")
		args = append(args, part)
	}

	g.writef("Pulumi::Output.format(%s", quote(format.String()))
	for _, arg := range args {
		g.writef(", ")
		g.genExpression(arg)
	}
	g.writef(")")
}

// templateLiteral returns the constant text of a template with no interpolations.
func templateLiteral(expr *model.TemplateExpression) (string, bool) {
	var out strings.Builder
	for _, part := range expr.Parts {
		literal, ok := part.(*model.LiteralValueExpression)
		if !ok || literal.Value.Type() != cty.String {
			return "", false
		}
		out.WriteString(literal.Value.AsString())
	}
	return out.String(), true
}

func (g *generator) genTuple(expr *model.TupleConsExpression) {
	if len(expr.Expressions) == 0 {
		g.writef("[]")
		return
	}

	g.writef("[")
	g.indented(func() {
		for _, element := range expr.Expressions {
			g.newline()
			g.genExpression(element)
			g.writef(",")
		}
	})
	g.newline()
	g.writef("]")
}

func (g *generator) genObject(expr *model.ObjectConsExpression) {
	if len(expr.Items) == 0 {
		g.writef("{}")
		return
	}

	g.writef("{")
	g.indented(func() {
		for _, item := range expr.Items {
			g.newline()
			// String keys rather than symbols: a PCL object's keys are provider property
			// names, which can be any string at all -- the suite has keys with spaces and
			// with none -- and the SDK accepts either.
			g.genExpression(item.Key)
			g.writef(" => ")
			g.genExpression(item.Value)
			g.writef(",")
		}
	})
	g.newline()
	g.writef("}")
}

func (g *generator) genScopeTraversal(expr *model.ScopeTraversalExpression) {
	g.writef("%s", localName(expr.RootName))
	g.genTraversalParts(expr.Parts, expr.Traversal[1:])
}

func (g *generator) genRelativeTraversal(expr *model.RelativeTraversalExpression) {
	g.genExpression(expr.Source)
	g.genTraversalParts(expr.Parts, expr.Traversal)
}

// genTraversalParts renders `.foo` / `[0]` steps as Ruby index reads.
//
// Everything is read with `[]` rather than a method call, because the values being walked
// are plain Hashes and Arrays from the wire, not objects with readers.
func (g *generator) genTraversalParts(_ []model.Traversable, traversal hcl.Traversal) {
	for _, part := range traversal {
		switch part := part.(type) {
		case hcl.TraverseAttr:
			g.writef("[%s]", quote(part.Name))
		case hcl.TraverseIndex:
			switch part.Key.Type() {
			case cty.Number:
				g.writef("[%s]", formatNumber(part.Key.AsBigFloat()))
			case cty.String:
				g.writef("[%s]", quote(part.Key.AsString()))
			default:
				g.unsupportedf(part.SrcRange, "the index type %v is not supported", part.Key.Type())
			}
		default:
			g.unsupportedf(traversal.SourceRange(), "the traversal %T is not supported", part)
		}
	}
}

func (g *generator) genIndex(expr *model.IndexExpression) {
	g.genExpression(expr.Collection)
	g.writef("[")
	g.genExpression(expr.Key)
	g.writef("]")
}

func (g *generator) genBinaryOp(expr *model.BinaryOpExpression) {
	op, ok := binaryOperators[expr.Operation]
	if !ok {
		g.unsupportedf(expr.SyntaxNode().Range(), "the operator %v is not supported", expr.Operation)
		g.writef("nil")
		return
	}

	g.writef("(")
	g.genExpression(expr.LeftOperand)
	g.writef(" %s ", op)
	g.genExpression(expr.RightOperand)
	g.writef(")")
}

func (g *generator) genUnaryOp(expr *model.UnaryOpExpression) {
	op, ok := unaryOperators[expr.Operation]
	if !ok {
		g.unsupportedf(expr.SyntaxNode().Range(), "the operator %v is not supported", expr.Operation)
		g.writef("nil")
		return
	}

	g.writef("%s", op)
	g.genExpression(expr.Operand)
}

func (g *generator) genConditional(expr *model.ConditionalExpression) {
	g.writef("(")
	g.genExpression(expr.Condition)
	g.writef(" ? ")
	g.genExpression(expr.TrueResult)
	g.writef(" : ")
	g.genExpression(expr.FalseResult)
	g.writef(")")
}

func (g *generator) genAnonymousFunction(expr *model.AnonymousFunctionExpression) {
	g.writef("lambda { |")
	for i, param := range expr.Parameters {
		if i > 0 {
			g.writef(", ")
		}
		g.writef("%s", localName(param.Name))
	}
	g.writef("| ")
	g.genExpression(expr.Body)
	g.writef(" }")
}
