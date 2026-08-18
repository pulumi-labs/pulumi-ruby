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
	"unicode"
)

// rubyKeywords are the words Ruby will not accept as a local variable or method name.
//
// A PCL program may legitimately use any of them -- the conformance suite has a test that
// does exactly that -- so a name that collides gets a trailing underscore, which is the
// conventional Ruby escape and what a person would write by hand.
var rubyKeywords = map[string]bool{
	"BEGIN": true, "END": true, "alias": true, "and": true, "begin": true, "break": true,
	"case": true, "class": true, "def": true, "defined?": true, "do": true, "else": true,
	"elsif": true, "end": true, "ensure": true, "false": true, "for": true, "if": true,
	"in": true, "module": true, "next": true, "nil": true, "not": true, "or": true,
	"redo": true, "rescue": true, "retry": true, "return": true, "self": true, "super": true,
	"then": true, "true": true, "undef": true, "unless": true, "until": true, "when": true,
	"while": true, "yield": true, "__FILE__": true, "__LINE__": true, "__ENCODING__": true,
}

// localName converts a PCL identifier into a Ruby local variable name: snake_case, with
// keywords escaped.
func localName(name string) string {
	snake := toSnakeCase(name)
	if rubyKeywords[snake] {
		return snake + "_"
	}
	return snake
}

// toSnakeCase converts camelCase, PascalCase or kebab-case to Ruby's snake_case.
//
// Runs of capitals are kept together, so `HTTPServer` becomes `http_server` rather than
// `h_t_t_p_server`, matching what pkg/codegen/python does for the same reason.
func toSnakeCase(name string) string {
	if name == "" {
		return name
	}

	var out strings.Builder
	runes := []rune(name)
	for i, r := range runes {
		switch r {
		case '-', ' ', '_':
			out.WriteRune('_')
			continue
		}

		if unicode.IsUpper(r) {
			// A boundary is a lower-to-upper transition, or the last capital of a run that
			// is followed by a lowercase letter (the start of the next word).
			prevLower := i > 0 && (unicode.IsLower(runes[i-1]) || unicode.IsDigit(runes[i-1]))
			nextLower := i+1 < len(runes) && unicode.IsLower(runes[i+1])
			prevUpper := i > 0 && unicode.IsUpper(runes[i-1])
			if i > 0 && (prevLower || (prevUpper && nextLower)) && !strings.HasSuffix(out.String(), "_") {
				out.WriteRune('_')
			}
			out.WriteRune(unicode.ToLower(r))
			continue
		}

		out.WriteRune(r)
	}
	return out.String()
}
