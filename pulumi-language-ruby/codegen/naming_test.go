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
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestToSnakeCase(t *testing.T) {
	t.Parallel()

	for input, expected := range map[string]string{
		"":               "",
		"simple":         "simple",
		"camelCase":      "camel_case",
		"PascalCase":     "pascal_case",
		"kebab-case":     "kebab_case",
		"already_snake":  "already_snake",
		"withNumber2":    "with_number2",
		"aNumber":        "a_number",
		"optionalNumber": "optional_number",
		// A run of capitals is one word: http_server, not h_t_t_p_server.
		"HTTPServer": "http_server",
		"parseJSON":  "parse_json",
		"anID":       "an_id",
	} {
		assert.Equal(t, expected, toSnakeCase(input), "for %q", input)
	}
}

func TestLocalName(t *testing.T) {
	t.Parallel()

	assert.Equal(t, "bucket", localName("bucket"))
	assert.Equal(t, "my_bucket", localName("myBucket"))

	// A PCL program may use a name that is a Ruby keyword; the conformance suite has a
	// test that uses several. A trailing underscore is the conventional escape.
	for _, keyword := range []string{"class", "end", "if", "self", "module", "def", "nil"} {
		assert.Equal(t, keyword+"_", localName(keyword), "for %q", keyword)
	}

	// Words that are keywords elsewhere but not in Ruby stay as they are.
	assert.Equal(t, "export", localName("export"))
	assert.Equal(t, "import", localName("import"))
	assert.Equal(t, "this", localName("this"))
}
