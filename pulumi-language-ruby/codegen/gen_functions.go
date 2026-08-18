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
	"github.com/hashicorp/hcl/v2/hclsyntax"
	"github.com/pulumi/pulumi/pkg/v3/codegen/hcl2/model"
	"github.com/pulumi/pulumi/pkg/v3/codegen/pcl"
)

// binaryOperators maps HCL's operators onto Ruby's.
//
// The spellings coincide for everything except the logical connectives, where `&&` and
// `||` are used rather than `and`/`or`: the word forms bind far more loosely in Ruby and
// would change the meaning of an expression this generator has already parenthesised.
var binaryOperators = map[*hclsyntax.Operation]string{
	hclsyntax.OpAdd:                "+",
	hclsyntax.OpSubtract:           "-",
	hclsyntax.OpMultiply:           "*",
	hclsyntax.OpDivide:             "/",
	hclsyntax.OpModulo:             "%",
	hclsyntax.OpEqual:              "==",
	hclsyntax.OpNotEqual:           "!=",
	hclsyntax.OpGreaterThan:        ">",
	hclsyntax.OpGreaterThanOrEqual: ">=",
	hclsyntax.OpLessThan:           "<",
	hclsyntax.OpLessThanOrEqual:    "<=",
	hclsyntax.OpLogicalAnd:         "&&",
	hclsyntax.OpLogicalOr:          "||",
}

var unaryOperators = map[*hclsyntax.Operation]string{
	hclsyntax.OpLogicalNot: "!",
	hclsyntax.OpNegate:     "-",
}

// genFunctionCall emits the Ruby for a PCL intrinsic or standard-library function.
func (g *generator) genFunctionCall(expr *model.FunctionCallExpression) {
	switch expr.Name {
	case pcl.IntrinsicConvert:
		// A conversion the binder inserted to satisfy a type. Ruby is dynamically typed
		// and the SDK coerces at the wire boundary, so the conversion is a no-op here.
		g.genExpression(expr.Args[0])

	case pcl.IntrinsicApply:
		g.genApply(expr)

	case "secret":
		g.genCall("Pulumi::Output.secret", expr.Args)
	case "unsecret":
		g.genCall("Pulumi::Output.unsecret", expr.Args)
	case "toJSON":
		g.genCall("Pulumi::Output.json_dump", expr.Args)
	case "fromJSON":
		g.genCall("Pulumi::Output.json_parse", expr.Args)
	case "toBase64":
		g.genMethodCall(expr.Args[0], `pack("m0")`, true)
	case "fromBase64":
		g.genMethodCall(expr.Args[0], `unpack1("m")`, false)
	case "join":
		// join(separator, list) -> list.join(separator)
		g.genExpression(expr.Args[1])
		g.writef(".join(")
		g.genExpression(expr.Args[0])
		g.writef(")")
	case "length":
		g.genMethodCall(expr.Args[0], "length", false)
	case "toLowerCase":
		g.genMethodCall(expr.Args[0], "downcase", false)
	case "toUpperCase":
		g.genMethodCall(expr.Args[0], "upcase", false)
	case "sha1":
		// Digest::SHA1 rather than a gem: it is in Ruby's standard library, and `require`
		// at the top of a generated program is cheaper than a dependency.
		g.needsDigest = true
		g.genCall("Digest::SHA1.hexdigest", expr.Args)
	case "split":
		// split(separator, string) -> string.split(separator)
		g.genExpression(expr.Args[1])
		g.writef(".split(")
		g.genExpression(expr.Args[0])
		g.writef(")")
	case "element":
		// element(list, index) -> list[index]
		g.genExpression(expr.Args[0])
		g.writef("[")
		g.genExpression(expr.Args[1])
		g.writef("]")
	case "entries":
		// entries(map) -> [{"key" => k, "value" => v}, ...], the shape PCL's `entries`
		// produces and which `for` expressions destructure.
		g.genExpression(expr.Args[0])
		g.writef(".map { |k, v| { \"key\" => k, \"value\" => v } }")
	case "max":
		g.genVariadicMath("max", expr.Args)
	case "min":
		g.genVariadicMath("min", expr.Args)
	case "abs":
		g.genMethodCall(expr.Args[0], "abs", false)
	case "floor":
		g.genMethodCall(expr.Args[0], "floor", false)
	case "ceil":
		g.genMethodCall(expr.Args[0], "ceil", false)
	case "range":
		g.genRange(expr.Args)
	case "notImplemented":
		// PCL emits this for a construct the converter could not translate; a generated
		// program should fail loudly at that point rather than quietly do nothing.
		g.writef("raise NotImplementedError, ")
		g.genExpression(expr.Args[0])
	case "singleOrNone":
		// Asserts the collection holds exactly one element and returns it.
		g.genExpression(expr.Args[0])
		g.writef(".then { |items| items.length == 1 ? items[0] : raise(\"expected a single element\") }")
	case "rootDirectory":
		g.writef("Pulumi.root_directory")
	case "requirePulumiVersion":
		g.genCall("Pulumi.require_version", expr.Args)
	case "readFile":
		g.genCall("File.read", expr.Args)
	case "readDir":
		g.genCall("Dir.children", expr.Args)
	case "cwd":
		g.writef("Dir.pwd")
	case "stack":
		g.writef("Pulumi.stack")
	case "project":
		g.writef("Pulumi.project")
	case "organization":
		g.writef("Pulumi.organization")
	case "getOutput":
		// getOutput(stackReference, name)
		g.genExpression(expr.Args[0])
		g.writef(".output(")
		g.genExpression(expr.Args[1])
		g.writef(")")

	default:
		g.unsupportedf(expr.SyntaxNode().Range(), "the function %q is not supported yet", expr.Name)
		g.writef("nil")
	}
}

// genVariadicMath emits `[a, b, c].max` / `.min`, which is how Ruby spells the variadic
// form; Ruby's Comparable#max is binary only.
func (g *generator) genVariadicMath(method string, args []model.Expression) {
	g.writef("[")
	for i, arg := range args {
		if i > 0 {
			g.writef(", ")
		}
		g.genExpression(arg)
	}
	g.writef("].%s", method)
}

// genRange emits PCL's range() as a Ruby Array.
//
// range(n) counts from zero; range(from, to) is exclusive of `to`, which is what `...`
// means in Ruby.
func (g *generator) genRange(args []model.Expression) {
	g.writef("(")
	if len(args) == 1 {
		g.writef("0...")
		g.genExpression(args[0])
	} else {
		g.genExpression(args[0])
		g.writef("...")
		g.genExpression(args[1])
	}
	g.writef(").to_a")
}

func (g *generator) genCall(name string, args []model.Expression) {
	g.writef("%s(", name)
	for i, arg := range args {
		if i > 0 {
			g.writef(", ")
		}
		g.genExpression(arg)
	}
	g.writef(")")
}

// genMethodCall emits `receiver.method`, wrapping the receiver in brackets when the method
// is one Ruby defines on Array rather than on the value itself (pack, for instance).
func (g *generator) genMethodCall(receiver model.Expression, method string, wrapInArray bool) {
	if wrapInArray {
		g.writef("[")
	}
	g.genExpression(receiver)
	if wrapInArray {
		g.writef("]")
	}
	g.writef(".%s", method)
}

// genApply emits the block form of Output#apply.
//
// PCL models "compute this once the inputs are known" as __apply(inputs..., fn). One input
// becomes a single apply; several become Output.all, whose block destructures the array.
func (g *generator) genApply(expr *model.FunctionCallExpression) {
	inputs, fn := pcl.ParseApplyCall(expr)

	if len(inputs) == 1 {
		g.genExpression(inputs[0])
		g.writef(".apply { |%s| ", localName(fn.Parameters[0].Name))
		g.genExpression(fn.Body)
		g.writef(" }")
		return
	}

	g.writef("Pulumi::Output.all(")
	for i, input := range inputs {
		if i > 0 {
			g.writef(", ")
		}
		g.genExpression(input)
	}
	g.writef(").apply { |(")
	for i, param := range fn.Parameters {
		if i > 0 {
			g.writef(", ")
		}
		g.writef("%s", localName(param.Name))
	}
	g.writef(")| ")
	g.genExpression(fn.Body)
	g.writef(" }")
}
