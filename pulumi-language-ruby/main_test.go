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

package main

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	pulumirpc "github.com/pulumi/pulumi/sdk/v3/proto/go"
)

func TestPackageDependencyFromGem(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name     string
		gem      gemInfo
		expected *pulumirpc.PackageDependency
	}{
		{
			name: "derives plugin name from gem name",
			gem:  gemInfo{Name: "pulumi-aws", Version: "6.1.0"},
			expected: &pulumirpc.PackageDependency{
				Kind: "resource", Name: "aws", Version: "6.1.0",
			},
		},
		{
			name: "pulumi-plugin.json overrides name and version",
			gem: gemInfo{
				Name: "pulumi-aws", Version: "6.1.0",
				PluginJSON: `{"resource":true,"name":"aws-native","version":"1.2.3","server":"https://example.com"}`,
			},
			expected: &pulumirpc.PackageDependency{
				Kind: "resource", Name: "aws-native", Version: "1.2.3", Server: "https://example.com",
			},
		},
		{
			// A gem can ship Pulumi code without having a plugin of its own -- policy packs
			// and pure-utility gems do. `resource: false` is how they say so.
			name:     "resource:false suppresses the dependency",
			gem:      gemInfo{Name: "pulumi-std", Version: "1.0.0", PluginJSON: `{"resource":false}`},
			expected: nil,
		},
		{
			name: "pulumi-plugin.json without a name still strips the gem prefix",
			gem: gemInfo{
				Name: "pulumi-random", Version: "4.0.0",
				PluginJSON: `{"resource":true,"version":"4.16.0"}`,
			},
			expected: &pulumirpc.PackageDependency{
				Kind: "resource", Name: "random", Version: "4.16.0",
			},
		},
		{
			name: "parameterization is carried through",
			gem: gemInfo{
				Name: "pulumi-mypkg", Version: "1.0.0",
				PluginJSON: `{"resource":true,"parameterization":` +
					`{"name":"base","version":"0.1.0","value":"aGk="}}`,
			},
			expected: &pulumirpc.PackageDependency{
				Kind: "resource", Name: "mypkg", Version: "1.0.0",
				Parameterization: &pulumirpc.PackageParameterization{
					Name: "base", Version: "0.1.0", Value: []byte("hi"),
				},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			actual, err := packageDependencyFromGem(tt.gem)
			require.NoError(t, err)

			if tt.expected == nil {
				assert.Nil(t, actual)
				return
			}
			require.NotNil(t, actual)
			assert.Equal(t, tt.expected.Kind, actual.Kind)
			assert.Equal(t, tt.expected.Name, actual.Name)
			assert.Equal(t, tt.expected.Version, actual.Version)
			assert.Equal(t, tt.expected.Server, actual.Server)
			if tt.expected.Parameterization != nil {
				require.NotNil(t, actual.Parameterization)
				assert.Equal(t, tt.expected.Parameterization.Name, actual.Parameterization.Name)
				assert.Equal(t, tt.expected.Parameterization.Version, actual.Parameterization.Version)
				assert.Equal(t, tt.expected.Parameterization.Value, actual.Parameterization.Value)
			}
		})
	}
}

func TestPackageDependencyFromGemRejectsBadPluginJSON(t *testing.T) {
	t.Parallel()

	_, err := packageDependencyFromGem(gemInfo{Name: "pulumi-aws", PluginJSON: "{not json"})
	require.ErrorContains(t, err, "parsing pulumi-plugin.json for pulumi-aws")
}

func TestGemAndRequireNaming(t *testing.T) {
	t.Parallel()

	assert.Equal(t, "pulumi-aws", gemNameForPackage("aws"))
	assert.Equal(t, "pulumi-aws", gemNameForPackage("pulumi-aws"))
	assert.Equal(t, "pulumi", gemNameForPackage("pulumi"))

	assert.Equal(t, "pulumi/aws", requirePathForPackage("aws"))
	assert.Equal(t, "pulumi/aws", requirePathForPackage("pulumi-aws"))
}

func TestFindGemspec(t *testing.T) {
	t.Parallel()

	t.Run("finds the single gemspec", func(t *testing.T) {
		t.Parallel()

		dir := t.TempDir()
		require.NoError(t, os.WriteFile(filepath.Join(dir, "pulumi.gemspec"), nil, 0o600))
		require.NoError(t, os.WriteFile(filepath.Join(dir, "Gemfile"), nil, 0o600))

		found, err := findGemspec(dir)
		require.NoError(t, err)
		assert.Equal(t, "pulumi.gemspec", found)
	})

	t.Run("errors when there is none", func(t *testing.T) {
		t.Parallel()

		_, err := findGemspec(t.TempDir())
		require.ErrorContains(t, err, "no .gemspec found")
	})

	t.Run("errors rather than guessing when ambiguous", func(t *testing.T) {
		t.Parallel()

		dir := t.TempDir()
		require.NoError(t, os.WriteFile(filepath.Join(dir, "a.gemspec"), nil, 0o600))
		require.NoError(t, os.WriteFile(filepath.Join(dir, "b.gemspec"), nil, 0o600))

		_, err := findGemspec(dir)
		require.ErrorContains(t, err, "expected exactly one .gemspec")
	})
}

func TestToolchainDetectsBundler(t *testing.T) {
	t.Parallel()

	t.Run("with a Gemfile", func(t *testing.T) {
		t.Parallel()

		dir := t.TempDir()
		require.NoError(t, os.WriteFile(filepath.Join(dir, "Gemfile"), nil, 0o600))

		tc, err := newToolchain(dir, "")
		require.NoError(t, err)
		assert.True(t, tc.usesBundler())
	})

	t.Run("without a Gemfile", func(t *testing.T) {
		t.Parallel()

		tc, err := newToolchain(t.TempDir(), "")
		require.NoError(t, err)
		assert.False(t, tc.usesBundler())
	})

	// `main:` in Pulumi.yaml points the program at a subdirectory while the Gemfile stays
	// at the project root, next to Pulumi.yaml. Looking only in the program directory made
	// such a project resolve no dependencies at all.
	t.Run("with a Gemfile only at the project root", func(t *testing.T) {
		t.Parallel()

		root := t.TempDir()
		program := filepath.Join(root, "subdir")
		require.NoError(t, os.MkdirAll(program, 0o700))
		require.NoError(t, os.WriteFile(filepath.Join(root, "Gemfile"), nil, 0o600))

		tc, err := newToolchain(program, root)
		require.NoError(t, err)
		assert.True(t, tc.usesBundler())
		assert.Equal(t, filepath.Join(root, "Gemfile"), tc.gemfile)
	})

	// A Gemfile beside the program wins over one at the root, so a nested program can
	// declare its own dependencies.
	t.Run("prefers the program's own Gemfile", func(t *testing.T) {
		t.Parallel()

		root := t.TempDir()
		program := filepath.Join(root, "subdir")
		require.NoError(t, os.MkdirAll(program, 0o700))
		require.NoError(t, os.WriteFile(filepath.Join(root, "Gemfile"), nil, 0o600))
		require.NoError(t, os.WriteFile(filepath.Join(program, "Gemfile"), nil, 0o600))

		tc, err := newToolchain(program, root)
		require.NoError(t, err)
		assert.Equal(t, filepath.Join(program, "Gemfile"), tc.gemfile)
	})
}

func TestConstructArguments(t *testing.T) {
	t.Parallel()

	host := &rubyLanguageHost{engineAddress: "127.0.0.1:1234"}
	args := host.constructArguments(&pulumirpc.RunRequest{
		MonitorAddress: "127.0.0.1:5678",
		Project:        "proj",
		Stack:          "dev",
		Pwd:            "/tmp/proj",
		DryRun:         true,
		Parallel:       8,
		Organization:   "acme",
		Info: &pulumirpc.ProgramInfo{
			RootDirectory:    "/tmp/proj",
			ProgramDirectory: "/tmp/proj",
			EntryPoint:       "main.rb",
		},
		Args: []string{"--flag"},
	})

	assert.Equal(t, []string{
		"--monitor", "127.0.0.1:5678",
		"--engine", "127.0.0.1:1234",
		"--project", "proj",
		"--root-directory", "/tmp/proj",
		"--stack", "dev",
		"--pwd", "/tmp/proj",
		"--dry-run", "true",
		"--parallel", "8",
		"--organization", "acme",
		"main.rb",
		"--flag",
	}, args)
}

func TestMarshalConfig(t *testing.T) {
	t.Parallel()

	// A nil config must serialize to the empty string, not "null": the shim treats an
	// unset PULUMI_CONFIG as "no config" and would otherwise have to special-case a
	// literal null.
	config, err := marshalConfig(nil)
	require.NoError(t, err)
	assert.Empty(t, config)

	config, err = marshalConfig(map[string]string{"proj:key": "value"})
	require.NoError(t, err)
	assert.JSONEq(t, `{"proj:key":"value"}`, config)

	// Secret keys, by contrast, must always be a JSON array so the shim can parse
	// unconditionally.
	keys, err := marshalConfigSecretKeys(nil)
	require.NoError(t, err)
	assert.Equal(t, "[]", keys)

	keys, err = marshalConfigSecretKeys([]string{"proj:secret"})
	require.NoError(t, err)
	assert.JSONEq(t, `["proj:secret"]`, keys)
}

func TestReplaceGemDirective(t *testing.T) {
	t.Parallel()

	// Re-linking must update the existing directive rather than append a second one,
	// which Bundler rejects outright.
	content := "source \"https://rubygems.org\"\ngem \"pulumi\", path: \"/old\"\ngem \"rake\"\n"
	updated := replaceGemDirective(content, "pulumi", `gem "pulumi", path: "/new"`)

	assert.Equal(t, "source \"https://rubygems.org\"\ngem \"pulumi\", path: \"/new\"\ngem \"rake\"\n", updated)
}

func TestGemNameFromArtifact(t *testing.T) {
	t.Parallel()

	// Pack names the unpacked directory after the gem alone, so that anything depending on
	// the path survives a version bump. RubyGems forbids a digit right after the final
	// hyphen of a name, which is what makes this decomposition unambiguous.
	tests := map[string]string{
		"pulumi-0.1.0.gem":                "pulumi",
		"pulumi-aws-6.1.0.gem":            "pulumi-aws",
		"pulumi-azure-native-2.0.0.gem":   "pulumi-azure-native",
		"pulumi-1.0.0.pre.rc1.gem":        "pulumi",
		"/tmp/artifacts/pulumi-0.1.0.gem": "pulumi",
		// A name with no version at all is returned unchanged rather than truncated.
		"pulumi.gem": "pulumi",
	}

	for artifact, expected := range tests {
		assert.Equal(t, expected, gemNameFromArtifact(artifact), "for %s", artifact)
	}
}
