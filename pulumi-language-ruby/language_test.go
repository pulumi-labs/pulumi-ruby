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
	"fmt"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"

	"github.com/pulumi/pulumi/pkg/v3/testing/pulumi-test-language/runner"
	"github.com/pulumi/pulumi/pkg/v3/testing/pulumi-test-language/tests"
	"github.com/pulumi/pulumi/sdk/v3/go/common/util/contract"
	"github.com/pulumi/pulumi/sdk/v3/go/common/util/rpcutil"
	pulumirpc "github.com/pulumi/pulumi/sdk/v3/proto/go"
	testingrpc "github.com/pulumi/pulumi/sdk/v3/proto/go/testing"
)

// coreSDKVersion must match sdk/ruby/lib/pulumi/version.rb. The harness asserts that a
// program's reported dependencies include the core SDK at this version, which is what
// catches a host reporting dependencies it is not actually using.
const coreSDKVersion = "0.1.0"

// expectedFailures maps conformance test names to the reason they are currently skipped.
// Entries here are honest debt: each one is a feature the Ruby implementation does not
// support yet.
//
// Nothing is skipped by prefix or by category, so the size of this map is exactly the
// remaining work.
var expectedFailures = map[string]string{
	// Needs program generation work. Each is a specific construct the generator does
	// not translate yet; the SDK itself supports them.
	"l1-builtin-can":                    "the `can` builtin is not generated yet",
	"l1-builtin-file":                   "the `readFile`/`filebase64` builtins are not generated yet",
	"l1-builtin-list":                   "list builtins beyond `element` are not generated yet",
	"l1-builtin-object":                 "object builtins beyond `entries` are not generated yet",
	"l1-builtin-project-root-main":      "projectRoot with a `main:` subdirectory is not resolved correctly",
	"l1-builtin-require-pulumi-version": "requirePulumiVersion needs the engine's version check wired through the SDK",
	"l1-builtin-stash":                  "the Stash resource is not implemented in the SDK",
	"l1-builtin-string":                 "string builtins beyond `split` are not generated yet",
	"l1-builtin-try":                    "the `try` builtin is not generated yet",
	"l1-elide-index":                    "index elision over a resource's outputs is not generated correctly",
	"l1-expand-final":                   "final-argument expansion is not generated yet",
	"l1-main":                           "a `main:` subdirectory is not honoured when generating the project layout",
	"l1-stack-reference":                "getOutput on a generated StackReference does not resolve",

	// Needs SDK generation. Every one of these uses a provider, so the program cannot
	// be written -- with or without a generator -- until `pulumi package gen-sdk
	// --language ruby` produces the package. This is the single largest piece of
	// remaining work, and it is what unblocks the bulk of the suite.
	"l2-builtin-object":                            "needs SDK generation",
	"l2-camel-names":                               "needs SDK generation",
	"l2-component-call-plain":                      "needs SDK generation",
	"l2-component-call-simple":                     "needs SDK generation",
	"l2-component-component-resource-ref":          "needs SDK generation",
	"l2-component-program-resource-ref":            "needs SDK generation",
	"l2-component-property-deps":                   "needs SDK generation",
	"l2-config-default-from-invoke":                "needs SDK generation",
	"l2-destroy":                                   "needs SDK generation",
	"l2-discriminated-union":                       "needs SDK generation",
	"l2-docs":                                      "needs SDK generation",
	"l2-elide-index":                               "needs SDK generation",
	"l2-engine-update-options":                     "needs SDK generation",
	"l2-enum":                                      "needs SDK generation",
	"l2-explicit-parameterized-provider":           "needs SDK generation",
	"l2-explicit-provider":                         "needs SDK generation",
	"l2-explicit-providers":                        "needs SDK generation",
	"l2-extension-and-base-resource":               "needs SDK generation",
	"l2-extension-parameterized-resource":          "needs SDK generation",
	"l2-external-enum":                             "needs SDK generation",
	"l2-failed-create":                             "needs SDK generation",
	"l2-failed-create-continue-on-error":           "needs SDK generation",
	"l2-failed-create-recover-continue-on-error":   "needs SDK generation",
	"l2-id-type":                                   "needs SDK generation",
	"l2-index-mod":                                 "needs SDK generation",
	"l2-invoke-dependencies":                       "needs SDK generation",
	"l2-invoke-depends-on-component":               "needs SDK generation",
	"l2-invoke-multi-argument":                     "needs SDK generation",
	"l2-invoke-options":                            "needs SDK generation",
	"l2-invoke-options-depends-on":                 "needs SDK generation",
	"l2-invoke-output-only":                        "needs SDK generation",
	"l2-invoke-scalar":                             "needs SDK generation",
	"l2-invoke-scalars":                            "needs SDK generation",
	"l2-invoke-secrets":                            "needs SDK generation",
	"l2-invoke-simple":                             "needs SDK generation",
	"l2-invoke-variants":                           "needs SDK generation",
	"l2-keywords":                                  "needs SDK generation",
	"l2-large-string":                              "needs SDK generation",
	"l2-logical-name":                              "needs SDK generation",
	"l2-map-keys":                                  "needs SDK generation",
	"l2-map-keys-adversarial":                      "needs SDK generation",
	"l2-module-format":                             "needs SDK generation",
	"l2-name-conflicts":                            "needs SDK generation",
	"l2-namespaced-provider":                       "needs SDK generation",
	"l2-parallel-resources":                        "needs SDK generation",
	"l2-parameterized-invoke":                      "needs SDK generation",
	"l2-parameterized-resource":                    "needs SDK generation",
	"l2-parameterized-resource-twice":              "needs SDK generation",
	"l2-plain":                                     "needs SDK generation",
	"l2-plain-component":                           "needs SDK generation",
	"l2-primitive-ref":                             "needs SDK generation",
	"l2-primitive-ref-optional":                    "needs SDK generation",
	"l2-provider-call":                             "needs SDK generation",
	"l2-provider-call-explicit":                    "needs SDK generation",
	"l2-provider-config-enum":                      "needs SDK generation",
	"l2-provider-grpc-config":                      "needs SDK generation",
	"l2-provider-grpc-config-schema-secret":        "needs SDK generation",
	"l2-provider-grpc-config-secret":               "needs SDK generation",
	"l2-proxy-index":                               "needs SDK generation",
	"l2-raw-string-bytes":                          "needs SDK generation",
	"l2-ref-ref":                                   "needs SDK generation",
	"l2-resource-alpha":                            "needs SDK generation",
	"l2-resource-any":                              "needs SDK generation",
	"l2-resource-asset-archive":                    "needs SDK generation",
	"l2-resource-config":                           "needs SDK generation",
	"l2-resource-config-objects":                   "needs SDK generation",
	"l2-resource-config-primitives":                "needs SDK generation",
	"l2-resource-const":                            "needs SDK generation",
	"l2-resource-elide-unknowns":                   "needs SDK generation",
	"l2-resource-hook-after-failure":               "needs SDK generation",
	"l2-resource-hook-ignore-errors":               "needs SDK generation",
	"l2-resource-hook-on-error":                    "needs SDK generation",
	"l2-resource-invoke-dynamic-function":          "needs SDK generation",
	"l2-resource-keyword-overlap":                  "needs SDK generation",
	"l2-resource-name-type":                        "needs SDK generation",
	"l2-resource-names":                            "needs SDK generation",
	"l2-resource-option-additional-secret-outputs": "needs SDK generation",
	"l2-resource-option-alias":                     "needs SDK generation",
	"l2-resource-option-custom-timeouts":           "needs SDK generation",
	"l2-resource-option-delete-before-replace":     "needs SDK generation",
	"l2-resource-option-deleted-with":              "needs SDK generation",
	"l2-resource-option-depends-on":                "needs SDK generation",
	"l2-resource-option-env-var-mappings":          "needs SDK generation",
	"l2-resource-option-hide-diffs":                "needs SDK generation",
	"l2-resource-option-hooks":                     "needs SDK generation",
	"l2-resource-option-ignore-changes":            "needs SDK generation",
	"l2-resource-option-import":                    "needs SDK generation",
	"l2-resource-option-plugin-download-url":       "needs SDK generation",
	"l2-resource-option-protect":                   "needs SDK generation",
	"l2-resource-option-replace-on-changes":        "needs SDK generation",
	"l2-resource-option-replace-with":              "needs SDK generation",
	"l2-resource-option-replacement-trigger":       "needs SDK generation",
	"l2-resource-option-retain-on-delete":          "needs SDK generation",
	"l2-resource-option-version":                   "needs SDK generation",
	"l2-resource-option-version-sdk":               "needs SDK generation",
	"l2-resource-optional":                         "needs SDK generation",
	"l2-resource-order":                            "needs SDK generation",
	"l2-resource-parent-inheritance":               "needs SDK generation",
	"l2-resource-primitive-conversions":            "needs SDK generation",
	"l2-resource-primitive-defaults":               "needs SDK generation",
	"l2-resource-primitives":                       "needs SDK generation",
	"l2-resource-provider-inheritance":             "needs SDK generation",
	"l2-resource-read":                             "needs SDK generation",
	"l2-resource-schema-secret":                    "needs SDK generation",
	"l2-resource-secret":                           "needs SDK generation",
	"l2-resource-simple":                           "needs SDK generation",
	"l2-snake-names":                               "needs SDK generation",
	"l2-target-up-skipped-create-output":           "needs SDK generation",
	"l2-target-up-with-new-dependency":             "needs SDK generation",
	"l2-union":                                     "needs SDK generation",
	"l3-component-config-objects":                  "needs SDK generation",
	"l3-component-config-primitives":               "needs SDK generation",
	"l3-component-invoke":                          "needs SDK generation",
	"l3-component-nested":                          "needs SDK generation",
	"l3-component-primitive-conversions":           "needs SDK generation",
	"l3-component-provider":                        "needs SDK generation",
	"l3-component-provider-inheritance":            "needs SDK generation",
	"l3-component-simple":                          "needs SDK generation",
	"l3-deferred-outputs":                          "needs SDK generation",
	"l3-for":                                       "needs SDK generation",
	"l3-for-resource":                              "needs SDK generation",
	"l3-range":                                     "needs SDK generation",
	"l3-range-bool-ref":                            "needs SDK generation",
	"l3-range-invoke-output-traversal":             "needs SDK generation",
	"l3-range-list-ref":                            "needs SDK generation",
	"l3-range-map-ref":                             "needs SDK generation",
	"l3-range-parent-scope":                        "needs SDK generation",
	"l3-range-resource-output-traversal":           "needs SDK generation",
	"l3-resource-keyword-overlap":                  "needs SDK generation",
	"l3-rewrite-conversions":                       "needs SDK generation",
	"l3-splat":                                     "needs SDK generation",
	"policy-config":                                "needs SDK generation",
	"policy-config-schema":                         "needs SDK generation",
	"policy-dryrun":                                "needs SDK generation",
	"policy-enforcement-config":                    "needs SDK generation",
	"policy-invalid":                               "needs SDK generation",
	"policy-remediate":                             "needs SDK generation",
	"policy-simple":                                "needs SDK generation",
	"policy-stack-config":                          "needs SDK generation",
	"policy-stack-tags":                            "needs SDK generation",
	"provider-alias-component":                     "needs SDK generation",
	"provider-builtin-info-component":              "needs SDK generation",
	"provider-ignore-changes-component":            "needs SDK generation",
	"provider-replacement-trigger-component":       "needs SDK generation",
	"provider-resource-component":                  "needs SDK generation",
}

// startTestingHost serves the conformance harness and returns a client for it.
//
// The harness is hosted in-process rather than built and spawned. pulumi-test-language's
// `main` is a thin wrapper over runner.Start, an ordinary exported function, so spawning a
// binary buys nothing -- and it costs correctness: a `main` package cannot be imported, so
// `go mod tidy` prunes the go.sum entries its transitive dependencies need and the build
// of the spawned binary then fails.
func startTestingHost(t *testing.T) (string, testingrpc.LanguageTestClient) {
	t.Helper()

	server, err := runner.Start(t.Context(), tests.LanguageTestdata, tests.LanguageTests)
	require.NoError(t, err)

	conn, err := grpc.NewClient(
		server.Address(),
		grpc.WithTransportCredentials(insecure.NewCredentials()),
		rpcutil.GrpcChannelOptions(),
	)
	require.NoError(t, err)

	t.Cleanup(func() { contract.IgnoreError(conn.Close()) })

	return server.Address(), testingrpc.NewLanguageTestClient(conn)
}

func TestLanguage(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping conformance tests in short mode")
	}
	t.Parallel()

	engineAddress, engine := startTestingHost(t)

	tests, err := engine.GetLanguageTests(t.Context(), &testingrpc.GetLanguageTestsRequest{})
	require.NoError(t, err)

	cancel := make(chan bool)

	// Run the language plugin in-process, so the test exercises this package directly.
	handle, err := rpcutil.ServeWithOptions(rpcutil.ServeOptions{
		Init: func(srv *grpc.Server) error {
			pulumirpc.RegisterLanguageRuntimeServer(srv, newLanguageHost(engineAddress, "", ""))
			return nil
		},
		Cancel: cancel,
	})
	require.NoError(t, err)

	rootDir := t.TempDir()

	prepare, err := engine.PrepareLanguageTests(t.Context(), &testingrpc.PrepareLanguageTestsRequest{
		LanguagePluginName:   "ruby",
		LanguagePluginTarget: fmt.Sprintf("127.0.0.1:%d", handle.Port),
		TemporaryDirectory:   rootDir,
		SnapshotDirectory:    "./testdata",
		CoreSdkDirectory:     "../sdk/ruby",
		CoreSdkVersion:       coreSDKVersion,
		SnapshotEdits: []*testingrpc.PrepareLanguageTestsRequest_Replacement{
			{
				Pattern:     rootDir + "/artifacts",
				Replacement: "ROOT/artifacts",
			},
		},
	})
	require.NoError(t, err)

	for _, tt := range tests.Tests {
		t.Run(tt, func(t *testing.T) {
			t.Parallel()

			if expected, ok := expectedFailures[tt]; ok {
				t.Skipf("test %s is expected to fail: %s", tt, expected)
			}

			result, err := engine.RunLanguageTest(t.Context(), &testingrpc.RunLanguageTestRequest{
				Token: prepare.Token,
				Test:  tt,
				// Convert additionally needs a converter plugin, which this suite does not
				// stand up; the harness only exercises it when ConverterPluginTarget is set.
				SkipConvertTests: true,
			}, grpc.MaxCallRecvMsgSize(1024*1024*1024))
			require.NoError(t, err)

			for _, msg := range result.Messages {
				t.Log(msg)
			}
			if !result.Success {
				t.Logf("stdout: %s", result.Stdout)
				t.Logf("stderr: %s", result.Stderr)
			}
			assert.True(t, result.Success)
		})
	}

	t.Cleanup(func() {
		close(cancel)
		assert.NoError(t, <-handle.Done)
	})
}
