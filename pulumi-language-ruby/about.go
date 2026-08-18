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
	"bytes"
	"context"
	"fmt"
	"os/exec"
	"regexp"
	"strings"

	pulumirpc "github.com/pulumi/pulumi/sdk/v3/proto/go"
)

// rubyVersionRegex extracts the semver from `ruby --version` output, which looks like
// "ruby 3.4.10 (2026-06-30 revision 2b0b7728dc) +PRISM [arm64-darwin23]".
var rubyVersionRegex = regexp.MustCompile(`^ruby (\d+\.\d+\.\d+)`)

func (host *rubyLanguageHost) About(
	ctx context.Context, req *pulumirpc.AboutRequest,
) (*pulumirpc.AboutResponse, error) {
	executable, err := exec.LookPath("ruby")
	if err != nil {
		return nil, fmt.Errorf("could not find `ruby` on $PATH: %w", err)
	}

	raw, err := runCapture(ctx, "ruby", "--version")
	if err != nil {
		return nil, err
	}

	version := raw
	if m := rubyVersionRegex.FindStringSubmatch(raw); m != nil {
		version = m[1]
	}

	metadata := map[string]string{}
	if bundler, err := runCapture(ctx, "bundle", "--version"); err == nil {
		// "Bundler version 2.6.9" -> "2.6.9"
		metadata["bundler"] = strings.TrimPrefix(bundler, "Bundler version ")
	}
	if gem, err := runCapture(ctx, "gem", "--version"); err == nil {
		metadata["rubygems"] = gem
	}

	return &pulumirpc.AboutResponse{
		Executable: executable,
		Version:    version,
		Metadata:   metadata,
	}, nil
}

func runCapture(ctx context.Context, name string, args ...string) (string, error) {
	cmd := exec.CommandContext(ctx, name, args...)

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("`%s %s` failed: %w\n%s", name, strings.Join(args, " "), err, stderr.String())
	}

	return strings.TrimSpace(stdout.String()), nil
}
