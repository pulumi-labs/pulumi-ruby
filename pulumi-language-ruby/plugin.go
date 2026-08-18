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
	"errors"
	"fmt"
	"os/exec"
	"path/filepath"

	"github.com/pulumi/pulumi/sdk/v3/go/common/util/contract"
	"github.com/pulumi/pulumi/sdk/v3/go/common/util/rpcutil"
	pulumirpc "github.com/pulumi/pulumi/sdk/v3/proto/go"
)

// defaultPluginEntryPoint is the file a Ruby plugin is assumed to start from when
// PulumiPlugin.yaml doesn't name one, mirroring `main.rb` for programs.
const defaultPluginEntryPoint = "main.rb"

// RunPlugin executes a Pulumi plugin -- a provider or analyzer -- written in Ruby.
//
// Unlike Run, a plugin is long-lived and its output is streamed back to the engine rather
// than inherited, so the engine can interleave it with everything else it is reporting.
func (host *rubyLanguageHost) RunPlugin(
	req *pulumirpc.RunPluginRequest, server pulumirpc.LanguageRuntime_RunPluginServer,
) error {
	if req.Info == nil {
		return errors.New("missing program info")
	}

	tc, err := newToolchain(req.Info.ProgramDirectory, req.Info.RootDirectory)
	if err != nil {
		return err
	}
	if err := tc.validate(); err != nil {
		return err
	}

	entryPoint := req.Info.EntryPoint
	if entryPoint == "" || entryPoint == "." {
		entryPoint = defaultPluginEntryPoint
	}

	// rpcutil owns the stdout/stderr-to-gRPC plumbing for every language host, so the
	// framing and terminal handling stay identical across languages.
	closer, stdout, stderr, err := rpcutil.MakeRunPluginStreams(server, false /*isTerminal*/)
	if err != nil {
		return err
	}
	defer contract.IgnoreClose(closer)

	args := append([]string{filepath.Join(req.Info.ProgramDirectory, entryPoint)}, req.Args...)
	cmd := tc.rubyCommand(server.Context(), args...)
	if req.Pwd != "" {
		cmd.Dir = req.Pwd
	}
	cmd.Env = append(cmd.Env, req.Env...)
	cmd.Stdout = stdout
	cmd.Stderr = stderr

	// A plugin exiting non-zero is information for the engine, not a transport failure, so
	// the code is reported rather than returned as an error.
	exitCode := 0
	if err := cmd.Run(); err != nil {
		var exitErr *exec.ExitError
		if !errors.As(err, &exitErr) {
			return fmt.Errorf("running plugin %s: %w", req.Name, err)
		}
		exitCode = exitErr.ExitCode()
	}

	if err := closer.Close(); err != nil {
		return err
	}

	return server.Send(&pulumirpc.RunPluginResponse{
		Output: &pulumirpc.RunPluginResponse_Exitcode{Exitcode: int32(exitCode)},
	})
}
