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
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"

	pulumirpc "github.com/pulumi/pulumi/sdk/v3/proto/go"
)

// Pack builds a gem from a package directory and returns a path another project can
// depend on.
//
// That path is a *directory*, not the .gem file, because the only way for one Ruby project
// to consume another from disk is Bundler's `path:`, which wants an unpacked source tree
// with a gemspec in it. The .gem is built first (it is what publishing needs, and building
// it is what proves the gemspec is valid) and then unpacked beside itself. The Go language
// host returns a directory here for the same reason.
//
// The directory is named for the gem alone, without the version, so that a project
// depending on it does not have to be edited every time the version changes.
func (host *rubyLanguageHost) Pack(
	ctx context.Context, req *pulumirpc.PackRequest,
) (*pulumirpc.PackResponse, error) {
	if req.PackageDirectory == "" {
		return nil, errors.New("package directory must not be empty")
	}
	if req.DestinationDirectory == "" {
		return nil, errors.New("destination directory must not be empty")
	}

	gemspec, err := findGemspec(req.PackageDirectory)
	if err != nil {
		return nil, err
	}

	// Passing --output an explicit path is the only way to learn the artifact's name
	// without scraping `gem build` output, which is not a stable interface.
	artifact, err := gemArtifactPath(ctx, req.PackageDirectory, gemspec, req.DestinationDirectory)
	if err != nil {
		return nil, err
	}

	// `gem build` is deliberately run outside Bundler: packing must depend only on the
	// gemspec, not on whatever the surrounding project happens to have resolved.
	cmd := exec.CommandContext(ctx, "gem", "build", gemspec, "--output", artifact)
	cmd.Dir = req.PackageDirectory

	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("`gem build %s` failed: %w\n%s", gemspec, err, stderr.String())
	}

	unpacked, err := unpackGem(ctx, artifact)
	if err != nil {
		return nil, err
	}

	return &pulumirpc.PackResponse{ArtifactPath: unpacked}, nil
}

// gemArtifactPath asks Ruby what the gemspec's name and version evaluate to, so the
// output filename matches RubyGems' own `<name>-<version>.gem` convention.
func gemArtifactPath(ctx context.Context, packageDirectory, gemspec, destination string) (string, error) {
	script := fmt.Sprintf(
		`spec = Gem::Specification.load(%q); print "#{spec.name}-#{spec.version}.gem"`, gemspec)

	cmd := exec.CommandContext(ctx, "ruby", "-e", script)
	cmd.Dir = packageDirectory

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("evaluating %s: %w\n%s", gemspec, err, stderr.String())
	}

	if err := os.MkdirAll(destination, 0o700); err != nil {
		return "", fmt.Errorf("creating destination directory: %w", err)
	}
	return filepath.Join(destination, stdout.String()), nil
}

// Link wires locally built gems into a program's Gemfile so it resolves them from disk
// rather than from RubyGems.
func (host *rubyLanguageHost) Link(
	ctx context.Context, req *pulumirpc.LinkRequest,
) (*pulumirpc.LinkResponse, error) {
	if req.Info == nil {
		return nil, errors.New("missing program info")
	}

	gemfile := filepath.Join(req.Info.ProgramDirectory, "Gemfile")
	existing, err := os.ReadFile(gemfile)
	if err != nil && !os.IsNotExist(err) {
		return nil, fmt.Errorf("reading Gemfile: %w", err)
	}

	content := string(existing)
	if content == "" {
		content = "source \"https://rubygems.org\"\n"
	}

	var instructions []string
	for _, dep := range req.Packages {
		if dep.Package == nil {
			continue
		}
		gemName := gemNameForPackage(dep.Package.Name)

		// Pack hands back an unpacked directory, which is what `path:` needs. A caller that
		// passes a .gem file directly is unpacked here for the same reason.
		source := dep.Path
		if filepath.Ext(source) == ".gem" {
			unpacked, err := unpackGem(ctx, source)
			if err != nil {
				return nil, err
			}
			source = unpacked
		}

		directive := fmt.Sprintf("gem %q, path: %q", gemName, source)
		if !strings.Contains(content, fmt.Sprintf("gem %q", gemName)) {
			if !strings.HasSuffix(content, "\n") {
				content += "\n"
			}
			content += directive + "\n"
		} else {
			content = replaceGemDirective(content, gemName, directive)
		}

		instructions = append(instructions, fmt.Sprintf("require %q", requirePathForPackage(dep.Package.Name)))
	}

	if err := os.WriteFile(gemfile, []byte(content), 0o600); err != nil {
		return nil, fmt.Errorf("writing Gemfile: %w", err)
	}

	sort.Strings(instructions)
	return &pulumirpc.LinkResponse{ImportInstructions: strings.Join(instructions, "\n")}, nil
}

// unpackGem expands a .gem archive beside itself and returns the directory.
//
// `gem unpack` creates `<name>-<version>/`; that is renamed to `<name>/` so that anything
// depending on the path does not have to change when the version does.
func unpackGem(ctx context.Context, gemPath string) (string, error) {
	dir := filepath.Dir(gemPath)
	versioned := strings.TrimSuffix(gemPath, ".gem")
	target := filepath.Join(dir, gemNameFromArtifact(gemPath))

	for _, path := range []string{versioned, target} {
		if err := os.RemoveAll(path); err != nil {
			return "", fmt.Errorf("clearing %s: %w", path, err)
		}
	}

	cmd := exec.CommandContext(ctx, "gem", "unpack", gemPath, "--target", dir)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("`gem unpack %s` failed: %w\n%s", gemPath, err, stderr.String())
	}

	if versioned != target {
		if err := os.Rename(versioned, target); err != nil {
			return "", fmt.Errorf("renaming %s to %s: %w", versioned, target, err)
		}
	}

	if err := writeGemspec(ctx, gemPath, target); err != nil {
		return "", err
	}
	return target, nil
}

// writeGemspec puts a gemspec into an unpacked gem directory.
//
// `gem unpack` extracts only the gem's files, so the result has no gemspec -- and Bundler
// refuses a `path:` source without one ("Could not find gem 'x' in source at ..."). The
// spec is taken from the built gem rather than copied from the source tree, because
// `gem specification --ruby` emits the *evaluated* form: no `Dir[]` globs, no
// `require_relative`, nothing that depends on the layout the gem was built from.
//
// Note that `gem unpack --spec` is not what is wanted here -- it writes YAML, and Bundler
// evaluates a .gemspec as Ruby.
func writeGemspec(ctx context.Context, gemPath, target string) error {
	cmd := exec.CommandContext(ctx, "gem", "specification", gemPath, "--ruby")

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("`gem specification %s --ruby` failed: %w\n%s", gemPath, err, stderr.String())
	}

	name := gemNameFromArtifact(gemPath)
	path := filepath.Join(target, name+".gemspec")
	if err := os.WriteFile(path, stdout.Bytes(), 0o600); err != nil {
		return fmt.Errorf("writing %s: %w", path, err)
	}
	return nil
}

// gemNameFromArtifact strips the version off a `<name>-<version>.gem` filename. RubyGems
// forbids a digit immediately after the final hyphen in a gem name, so the last hyphen
// that is followed by a digit is unambiguously the version separator.
func gemNameFromArtifact(gemPath string) string {
	base := strings.TrimSuffix(filepath.Base(gemPath), ".gem")
	for i := len(base) - 1; i > 0; i-- {
		if base[i] == '-' && i+1 < len(base) && base[i+1] >= '0' && base[i+1] <= '9' {
			return base[:i]
		}
	}
	return base
}

// replaceGemDirective rewrites an existing `gem "name", ...` line in place, so re-linking
// updates the path rather than appending a duplicate Bundler would reject.
func replaceGemDirective(content, gemName, directive string) string {
	lines := strings.Split(content, "\n")
	prefix := fmt.Sprintf("gem %q", gemName)
	for i, line := range lines {
		if strings.HasPrefix(strings.TrimSpace(line), prefix) {
			lines[i] = directive
			break
		}
	}
	return strings.Join(lines, "\n")
}

// gemNameForPackage maps a Pulumi package name onto its gem name: `aws` -> `pulumi-aws`.
func gemNameForPackage(name string) string {
	if strings.HasPrefix(name, "pulumi-") || name == "pulumi" {
		return name
	}
	return "pulumi-" + name
}

// requirePathForPackage maps a Pulumi package name onto the path a program requires:
// `aws` -> `pulumi/aws`.
func requirePathForPackage(name string) string {
	return "pulumi/" + strings.TrimPrefix(name, "pulumi-")
}

// Template runs after `pulumi new` has instantiated a template. Ruby templates ship a
// complete Gemfile, so there is nothing to rewrite -- unlike Python, which may need to
// convert a requirements.txt into a pyproject.toml.
func (host *rubyLanguageHost) Template(
	_ context.Context, _ *pulumirpc.TemplateRequest,
) (*pulumirpc.TemplateResponse, error) {
	return &pulumirpc.TemplateResponse{}, nil
}

// RuntimeOptionsPrompts returns additional prompts for `pulumi new`. Ruby has no
// meaningful choice to offer yet: Bundler is the only dependency manager in practice, and
// its use is implied by the presence of a Gemfile.
func (host *rubyLanguageHost) RuntimeOptionsPrompts(
	_ context.Context, _ *pulumirpc.RuntimeOptionsRequest,
) (*pulumirpc.RuntimeOptionsResponse, error) {
	return &pulumirpc.RuntimeOptionsResponse{}, nil
}

// findGemspec locates the single .gemspec in a directory. Packing is only well defined
// when there is exactly one, so an ambiguous directory is an error rather than a guess.
func findGemspec(dir string) (string, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return "", fmt.Errorf("reading %s: %w", dir, err)
	}

	var found []string
	for _, entry := range entries {
		if !entry.IsDir() && filepath.Ext(entry.Name()) == ".gemspec" {
			found = append(found, entry.Name())
		}
	}

	switch len(found) {
	case 0:
		return "", fmt.Errorf("no .gemspec found in %s", dir)
	case 1:
		return found[0], nil
	default:
		return "", fmt.Errorf("expected exactly one .gemspec in %s, found %d: %s",
			dir, len(found), strings.Join(found, ", "))
	}
}
