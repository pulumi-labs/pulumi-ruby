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
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"time"

	"github.com/pulumi/pulumi/sdk/v3/go/common/util/contract"
	pulumirpc "github.com/pulumi/pulumi/sdk/v3/proto/go"
)

const (
	pulumiConfigVar           = "PULUMI_CONFIG"
	pulumiConfigSecretKeysVar = "PULUMI_CONFIG_SECRET_KEYS"

	// execShim is the entrypoint the `pulumi` gem installs as a binstub. Shipping it in
	// the gem rather than alongside this binary keeps the shim and the SDK it loads at
	// the same version -- they are two halves of one contract.
	execShim = "pulumi-language-ruby-exec"

	// rubyProcessExitedAfterShowingUserActionableMessage is the exit code the shim uses to
	// say "I already printed something useful; don't add a generic error on top".
	rubyProcessExitedAfterShowingUserActionableMessage = 32
)

func (host *rubyLanguageHost) Run(ctx context.Context, req *pulumirpc.RunRequest) (*pulumirpc.RunResponse, error) {
	if req.Info == nil {
		return nil, errors.New("missing program info")
	}

	tc, err := newToolchain(req.Info.ProgramDirectory, req.Info.RootDirectory)
	if err != nil {
		return nil, err
	}
	if err := tc.validate(); err != nil {
		return nil, err
	}

	config, err := marshalConfig(req.GetConfig())
	if err != nil {
		return nil, fmt.Errorf("failed to serialize configuration: %w", err)
	}
	configSecretKeys, err := marshalConfigSecretKeys(req.GetConfigSecretKeys())
	if err != nil {
		return nil, fmt.Errorf("failed to serialize configuration secret keys: %w", err)
	}

	// The program stops either when the engine calls Cancel or when this RPC ends.
	runCtx, runCancel := context.WithCancel(host.cancelCtx)
	context.AfterFunc(ctx, runCancel)
	defer runCancel()

	cmd := tc.command(runCtx, execShim, host.constructArguments(req)...)
	cmd.Dir = req.GetPwd()
	if cmd.Dir == "" {
		cmd.Dir = req.Info.ProgramDirectory
	}
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Env = append(cmd.Env,
		pulumiConfigVar+"="+config,
		pulumiConfigSecretKeysVar+"="+configSecretKeys,
	)

	// Prefer a graceful interrupt so the SDK can drain in-flight resource registrations
	// and report a coherent error, and only escalate to a kill if it doesn't wind down.
	cmd.Cancel = func() error {
		if err := cmd.Process.Signal(os.Interrupt); err != nil {
			return cmd.Process.Kill()
		}
		return nil
	}
	cmd.WaitDelay = 5 * time.Second

	if err := cmd.Run(); err != nil {
		// Make sure anything the child wrote reaches the engine before we report failure;
		// a program that dies early is exactly when its output matters most.
		contract.IgnoreError(os.Stdout.Sync())
		contract.IgnoreError(os.Stderr.Sync())

		var exitErr *exec.ExitError
		if !errors.As(err, &exitErr) {
			// We never got as far as running the program.
			return nil, fmt.Errorf("problem executing program (could not run language executor): %w", err)
		}

		switch code := exitErr.ExitCode(); code {
		case 0:
			return &pulumirpc.RunResponse{
				Error: fmt.Sprintf("program exited unexpectedly: %v", exitErr),
			}, nil
		case rubyProcessExitedAfterShowingUserActionableMessage:
			return &pulumirpc.RunResponse{Bail: true}, nil
		default:
			return &pulumirpc.RunResponse{
				Error: fmt.Sprintf("program exited with non-zero exit code: %d", code),
			}, nil
		}
	}

	return &pulumirpc.RunResponse{}, nil
}

// constructArguments turns a RunRequest into the command line the Ruby shim expects.
func (host *rubyLanguageHost) constructArguments(req *pulumirpc.RunRequest) []string {
	var args []string
	appendArg := func(k, v string) {
		if v != "" {
			args = append(args, "--"+k, v)
		}
	}

	appendArg("monitor", req.GetMonitorAddress())
	appendArg("engine", host.getEngineAddress())
	appendArg("project", req.GetProject())
	appendArg("root-directory", req.GetInfo().GetRootDirectory())
	appendArg("stack", req.GetStack())
	appendArg("pwd", req.GetPwd())
	appendArg("dry-run", strconv.FormatBool(req.GetDryRun()))
	appendArg("parallel", strconv.Itoa(int(req.GetParallel())))
	appendArg("tracing", host.tracing)
	appendArg("organization", req.GetOrganization())

	// The engine always supplies an entry point, even if it is just "." for the program
	// directory itself.
	args = append(args, req.GetInfo().GetEntryPoint())
	return append(args, req.GetArgs()...)
}

func marshalConfig(config map[string]string) (string, error) {
	if config == nil {
		return "", nil
	}
	b, err := json.Marshal(config)
	return string(b), err
}

func marshalConfigSecretKeys(keys []string) (string, error) {
	if keys == nil {
		return "[]", nil
	}
	b, err := json.Marshal(keys)
	return string(b), err
}
