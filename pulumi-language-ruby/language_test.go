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
	"l1-builtin-can":                    "programgen: the `can` intrinsic",
	"l1-builtin-file":                   "programgen: the `readFile`/`filebase64` intrinsics",
	"l1-builtin-list":                   "programgen: list intrinsics beyond `element`",
	"l1-builtin-object":                 "programgen: object intrinsics beyond `entries`",
	"l1-builtin-project-root-main":      "programgen: projectRoot with a `main:` subdirectory",
	"l1-builtin-require-pulumi-version": "sdk: the engine version check is not wired through",
	"l1-builtin-stash":                  "sdk: the Stash resource is not implemented",
	"l1-builtin-string":                 "programgen: string intrinsics beyond `split`",
	"l1-builtin-try":                    "programgen: the `try` intrinsic",
	"l1-elide-index":                    "programgen: index elision over resource outputs",
	"l1-expand-final":                   "programgen: final-argument expansion",
	"l1-main":                           "programgen: a `main:` subdirectory in the project layout",
	"l1-stack-reference":                "programgen: getOutput on a generated StackReference",
	// Grouped by the first construct that blocks each test. The largest single
	// group is invokes, which need sdkgen to emit the function bindings; after that,
	// component and hook declarations in programgen.
	"l2-builtin-object":                            "sdkgen: type or function bindings not generated yet",
	"l2-camel-names":                               "sdkgen: type or function bindings not generated yet",
	"l2-component-call-plain":                      "programgen: the `call` intrinsic",
	"l2-component-call-simple":                     "programgen: the `call` intrinsic",
	"l2-component-component-resource-ref":          "sdkgen: type or function bindings not generated yet",
	"l2-component-program-resource-ref":            "programgen: the `invoke` intrinsic",
	"l2-component-property-deps":                   "sdkgen: type or function bindings not generated yet",
	"l2-config-default-from-invoke":                "programgen: Component declarations",
	"l2-destroy":                                   "sdkgen: type or function bindings not generated yet",
	"l2-docs":                                      "sdkgen: type or function bindings not generated yet",
	"l2-elide-index":                               "programgen: the `invoke` intrinsic",
	"l2-engine-update-options":                     "programgen: Component declarations",
	"l2-explicit-parameterized-provider":           "programgen: the `call` intrinsic",
	"l2-explicit-provider":                         "sdkgen: type or function bindings not generated yet",
	"l2-explicit-providers":                        "programgen: Component declarations",
	"l2-extension-and-base-resource":               "sdkgen: type or function bindings not generated yet",
	"l2-extension-parameterized-resource":          "programgen: the `invoke` intrinsic",
	"l2-failed-create":                             "sdkgen: type or function bindings not generated yet",
	"l2-failed-create-continue-on-error":           "sdkgen: type or function bindings not generated yet",
	"l2-failed-create-recover-continue-on-error":   "sdkgen: type or function bindings not generated yet",
	"l2-id-type":                                   "sdkgen: type or function bindings not generated yet",
	"l2-index-mod":                                 "sdkgen: type or function bindings not generated yet",
	"l2-invoke-dependencies":                       "programgen: the `invoke` intrinsic",
	"l2-invoke-depends-on-component":               "programgen: the `invoke` intrinsic",
	"l2-invoke-multi-argument":                     "programgen: the `invoke` intrinsic",
	"l2-invoke-options":                            "programgen: the `invoke` intrinsic",
	"l2-invoke-options-depends-on":                 "programgen: the `invoke` intrinsic",
	"l2-invoke-output-only":                        "programgen: the `invoke` intrinsic",
	"l2-invoke-scalar":                             "programgen: the `invoke` intrinsic",
	"l2-invoke-scalars":                            "sdkgen: type or function bindings not generated yet",
	"l2-invoke-secrets":                            "sdkgen: type or function bindings not generated yet",
	"l2-invoke-simple":                             "programgen: the `invoke` intrinsic",
	"l2-invoke-variants":                           "programgen: the `invoke` intrinsic",
	"l2-keywords":                                  "sdkgen: type or function bindings not generated yet",
	"l2-large-string":                              "programgen: the `stringAsset` intrinsic",
	"l2-logical-name":                              "sdkgen: type or function bindings not generated yet",
	"l2-map-keys-adversarial":                      "programgen: the `invoke` intrinsic",
	"l2-module-format":                             "sdkgen: type or function bindings not generated yet",
	"l2-name-conflicts":                            "sdkgen: type or function bindings not generated yet",
	"l2-namespaced-provider":                       "sdkgen: type or function bindings not generated yet",
	"l2-parallel-resources":                        "sdkgen: type or function bindings not generated yet",
	"l2-parameterized-invoke":                      "sdkgen: type or function bindings not generated yet",
	"l2-parameterized-resource":                    "programgen: ReadResource declarations",
	"l2-parameterized-resource-twice":              "sdkgen: type or function bindings not generated yet",
	"l2-plain-component":                           "sdkgen: type or function bindings not generated yet",
	"l2-primitive-ref-optional":                    "sdkgen: type or function bindings not generated yet",
	"l2-provider-call":                             "programgen: the `call` intrinsic",
	"l2-provider-call-explicit":                    "sdkgen: type or function bindings not generated yet",
	"l2-provider-config-enum":                      "sdkgen: type or function bindings not generated yet",
	"l2-provider-grpc-config":                      "sdkgen: type or function bindings not generated yet",
	"l2-provider-grpc-config-schema-secret":        "sdkgen: type or function bindings not generated yet",
	"l2-provider-grpc-config-secret":               "programgen: the `invoke` intrinsic",
	"l2-proxy-index":                               "sdkgen: type or function bindings not generated yet",
	"l2-raw-string-bytes":                          "sdkgen: type or function bindings not generated yet",
	"l2-resource-alpha":                            "sdkgen: type or function bindings not generated yet",
	"l2-resource-any":                              "sdkgen: type or function bindings not generated yet",
	"l2-resource-asset-archive":                    "programgen: the `invoke` intrinsic",
	"l2-resource-config":                           "sdkgen: type or function bindings not generated yet",
	"l2-resource-config-objects":                   "sdkgen: type or function bindings not generated yet",
	"l2-resource-config-primitives":                "programgen: the `invoke` intrinsic",
	"l2-resource-const":                            "sdkgen: type or function bindings not generated yet",
	"l2-resource-elide-unknowns":                   "sdkgen: type or function bindings not generated yet",
	"l2-resource-hook-after-failure":               "programgen: Hook declarations",
	"l2-resource-hook-ignore-errors":               "programgen: Hook declarations",
	"l2-resource-hook-on-error":                    "sdkgen: type or function bindings not generated yet",
	"l2-resource-invoke-dynamic-function":          "sdkgen: type or function bindings not generated yet",
	"l2-resource-keyword-overlap":                  "sdkgen: type or function bindings not generated yet",
	"l2-resource-name-type":                        "programgen: the `pulumiResourceName` intrinsic",
	"l2-resource-names":                            "sdkgen: type or function bindings not generated yet",
	"l2-resource-option-additional-secret-outputs": "sdkgen: type or function bindings not generated yet",
	"l2-resource-option-alias":                     "sdkgen: type or function bindings not generated yet",
	"l2-resource-option-custom-timeouts":           "programgen: the `invoke` intrinsic",
	"l2-resource-option-delete-before-replace":     "sdkgen: type or function bindings not generated yet",
	"l2-resource-option-deleted-with":              "sdkgen: type or function bindings not generated yet",
	"l2-resource-option-depends-on":                "programgen: the `invoke` intrinsic",
	"l2-resource-option-env-var-mappings":          "sdkgen: type or function bindings not generated yet",
	"l2-resource-option-hide-diffs":                "sdkgen: type or function bindings not generated yet",
	"l2-resource-option-hooks":                     "programgen: Hook declarations",
	"l2-resource-option-ignore-changes":            "sdkgen: type or function bindings not generated yet",
	"l2-resource-option-import":                    "sdkgen: type or function bindings not generated yet",
	"l2-resource-option-plugin-download-url":       "programgen: the `invoke` intrinsic",
	"l2-resource-option-protect":                   "sdkgen: type or function bindings not generated yet",
	"l2-resource-option-replace-on-changes":        "sdkgen: type or function bindings not generated yet",
	"l2-resource-option-replace-with":              "sdkgen: type or function bindings not generated yet",
	"l2-resource-option-replacement-trigger":       "sdkgen: type or function bindings not generated yet",
	"l2-resource-option-retain-on-delete":          "sdkgen: type or function bindings not generated yet",
	"l2-resource-option-version":                   "sdkgen: type or function bindings not generated yet",
	"l2-resource-option-version-sdk":               "sdkgen: type or function bindings not generated yet",
	"l2-resource-optional":                         "sdkgen: type or function bindings not generated yet",
	"l2-resource-order":                            "sdkgen: type or function bindings not generated yet",
	"l2-resource-parent-inheritance":               "sdkgen: type or function bindings not generated yet",
	"l2-resource-primitive-conversions":            "sdkgen: type or function bindings not generated yet",
	"l2-resource-primitive-defaults":               "sdkgen: type or function bindings not generated yet",
	"l2-resource-provider-inheritance":             "programgen: the `recover` intrinsic",
	"l2-resource-read":                             "sdkgen: type or function bindings not generated yet",
	"l2-resource-schema-secret":                    "sdkgen: type or function bindings not generated yet",
	"l2-resource-secret":                           "sdkgen: type or function bindings not generated yet",
	"l2-resource-simple":                           "sdkgen: type or function bindings not generated yet",
	"l2-snake-names":                               "programgen: Component declarations",
	"l2-target-up-skipped-create-output":           "sdkgen: type or function bindings not generated yet",
	"l2-target-up-with-new-dependency":             "sdkgen: type or function bindings not generated yet",
	"l2-union":                                     "sdkgen: type or function bindings not generated yet",
	"l3-component-config-objects":                  "programgen: Component declarations",
	"l3-component-config-primitives":               "sdkgen: type or function bindings not generated yet",
	"l3-component-invoke":                          "sdkgen: type or function bindings not generated yet",
	"l3-component-nested":                          "sdkgen: type or function bindings not generated yet",
	"l3-component-primitive-conversions":           "programgen: Component declarations",
	"l3-component-provider":                        "programgen: Component declarations",
	"l3-component-provider-inheritance":            "sdkgen: type or function bindings not generated yet",
	"l3-component-simple":                          "programgen: Component declarations",
	"l3-deferred-outputs":                          "programgen: Component declarations",
	"l3-for":                                       "programgen: ForExpression",
	"l3-for-resource":                              "programgen: ForExpression",
	"l3-range":                                     "sdkgen: type or function bindings not generated yet",
	"l3-range-bool-ref":                            "sdkgen: type or function bindings not generated yet",
	"l3-range-invoke-output-traversal":             "programgen: the `fileAsset` intrinsic",
	"l3-range-list-ref":                            "sdkgen: type or function bindings not generated yet",
	"l3-range-map-ref":                             "sdkgen: type or function bindings not generated yet",
	"l3-range-parent-scope":                        "sdkgen: type or function bindings not generated yet",
	"l3-range-resource-output-traversal":           "sdkgen: type or function bindings not generated yet",
	"l3-resource-keyword-overlap":                  "programgen: Component declarations",
	"l3-rewrite-conversions":                       "sdkgen: type or function bindings not generated yet",
	"l3-splat":                                     "programgen: SplatExpression",
	"policy-config":                                "sdkgen: type or function bindings not generated yet",
	"policy-config-schema":                         "sdkgen: type or function bindings not generated yet",
	"policy-dryrun":                                "sdkgen: type or function bindings not generated yet",
	"policy-enforcement-config":                    "programgen: Hook declarations",
	"policy-invalid":                               "programgen: the `invoke` intrinsic",
	"policy-remediate":                             "programgen: Component declarations",
	"policy-simple":                                "sdkgen: type or function bindings not generated yet",
	"policy-stack-config":                          "sdkgen: type or function bindings not generated yet",
	"policy-stack-tags":                            "programgen: the `lookup` intrinsic",
	"provider-alias-component":                     "sdkgen: type or function bindings not generated yet",
	"provider-builtin-info-component":              "sdkgen: type or function bindings not generated yet",
	"provider-ignore-changes-component":            "sdkgen: type or function bindings not generated yet",
	"provider-replacement-trigger-component":       "sdkgen: type or function bindings not generated yet",
	"provider-resource-component":                  "sdkgen: type or function bindings not generated yet",
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
