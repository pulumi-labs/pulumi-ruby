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
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
)

// toolchain resolves how to invoke Ruby for a particular program directory.
//
// Ruby's story here is mercifully simpler than Python's (pip/poetry/uv/virtualenv): a
// project either has a Gemfile, in which case Bundler owns dependency resolution and
// everything runs under `bundle exec`, or it doesn't, in which case we fall back to
// plain RubyGems resolution against whatever Ruby is on PATH. Those two cases are the
// entire matrix, so this is a struct rather than the interface Python needs.
type toolchain struct {
	// programDirectory is the directory containing the program (and its Gemfile, if any).
	programDirectory string
	// gemfile is the absolute path to the program's Gemfile, or "" when there isn't one.
	gemfile string
}

// newToolchain resolves how to run Ruby for a program.
//
// The Gemfile is looked for in the program directory first and then the project root,
// because `main:` in Pulumi.yaml can point the program at a subdirectory while the Gemfile
// stays at the root next to Pulumi.yaml -- which is where Bundler users expect it.
func newToolchain(programDirectory, rootDirectory string) (*toolchain, error) {
	if programDirectory == "" {
		return nil, errors.New("program directory must not be empty")
	}

	tc := &toolchain{programDirectory: programDirectory}

	for _, dir := range []string{programDirectory, rootDirectory} {
		if dir == "" {
			continue
		}

		gemfile := filepath.Join(dir, "Gemfile")
		if _, err := os.Stat(gemfile); err == nil {
			tc.gemfile = gemfile
			break
		} else if !os.IsNotExist(err) {
			return nil, fmt.Errorf("checking for Gemfile: %w", err)
		}
	}

	return tc, nil
}

// usesBundler reports whether commands should be run through `bundle exec`.
func (tc *toolchain) usesBundler() bool {
	return tc.gemfile != ""
}

// command builds a command that runs an executable installed by a gem -- either through
// Bundler when the project has a Gemfile, or directly from PATH otherwise.
//
// BUNDLE_GEMFILE is set explicitly rather than relying on Bundler walking up from the
// working directory: the engine can hand us a program directory that is nested below the
// project root, and we want the program's own Gemfile, not whichever one happens to be
// found first.
func (tc *toolchain) command(ctx context.Context, name string, args ...string) *exec.Cmd {
	var cmd *exec.Cmd
	if tc.usesBundler() {
		cmd = exec.CommandContext(ctx, "bundle", append([]string{"exec", name}, args...)...)
		cmd.Env = append(os.Environ(), "BUNDLE_GEMFILE="+tc.gemfile)
	} else {
		cmd = exec.CommandContext(ctx, name, args...)
		cmd.Env = os.Environ()
	}
	cmd.Dir = tc.programDirectory
	return cmd
}

// rubyCommand builds a command that runs `ruby` itself, under Bundler when applicable.
func (tc *toolchain) rubyCommand(ctx context.Context, args ...string) *exec.Cmd {
	return tc.command(ctx, "ruby", args...)
}

// bundleCommand builds a `bundle <args...>` command. Unlike command(), this invokes
// Bundler directly rather than running something under `bundle exec`.
func (tc *toolchain) bundleCommand(ctx context.Context, args ...string) *exec.Cmd {
	cmd := exec.CommandContext(ctx, "bundle", args...)
	cmd.Dir = tc.programDirectory
	cmd.Env = os.Environ()
	if tc.gemfile != "" {
		cmd.Env = append(cmd.Env, "BUNDLE_GEMFILE="+tc.gemfile)
	}
	return cmd
}

// validate checks that the tools we are about to invoke actually exist, so that a missing
// Ruby produces an actionable message rather than an opaque exec failure deep in a later
// RPC.
func (tc *toolchain) validate() error {
	if _, err := exec.LookPath("ruby"); err != nil {
		return errors.New("could not find `ruby` on $PATH. " +
			"Pulumi requires Ruby 3.3 or later; see https://www.ruby-lang.org/en/documentation/installation/")
	}
	if tc.usesBundler() {
		if _, err := exec.LookPath("bundle"); err != nil {
			return fmt.Errorf("found a Gemfile at %s but could not find `bundle` on $PATH. "+
				"Install Bundler with `gem install bundler`", tc.gemfile)
		}
	}
	return nil
}
