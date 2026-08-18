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
	_ "embed"
	"encoding/json"
	"errors"
	"fmt"
	"strings"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/pulumi/pulumi/sdk/v3/go/common/apitype"
	"github.com/pulumi/pulumi/sdk/v3/go/common/resource/plugin"
	"github.com/pulumi/pulumi/sdk/v3/go/common/util/contract"
	"github.com/pulumi/pulumi/sdk/v3/go/common/util/rpcutil"
	pulumirpc "github.com/pulumi/pulumi/sdk/v3/proto/go"
)

//go:embed scripts/list_packages.rb
var listPackagesScript string

// gemInfo is one entry of what scripts/list_packages.rb prints.
type gemInfo struct {
	Name       string `json:"name"`
	Version    string `json:"version"`
	GemDir     string `json:"gemDir"`
	PluginJSON string `json:"pluginJSON,omitempty"`
}

// listGems runs the introspection script against the program directory and decodes its
// output. When directOnly is set only the gems named in the Gemfile are reported, rather
// than the full transitive closure.
func (host *rubyLanguageHost) listGems(
	ctx context.Context, info *pulumirpc.ProgramInfo, directOnly bool,
) ([]gemInfo, error) {
	tc, err := newToolchain(info.ProgramDirectory, info.RootDirectory)
	if err != nil {
		return nil, err
	}
	if err := tc.validate(); err != nil {
		return nil, err
	}

	// The script is passed on stdin rather than written to a temp file: it keeps the
	// language host free of filesystem cleanup, and Ruby reads "-" as "the program is on
	// stdin" natively.
	args := []string{"-"}
	if directOnly {
		args = append(args, "--direct-only")
	}
	cmd := tc.rubyCommand(ctx, args...)
	cmd.Stdin = strings.NewReader(listPackagesScript)

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("listing gems: %w\n%s", err, stderr.String())
	}

	var gems []gemInfo
	if err := json.Unmarshal(stdout.Bytes(), &gems); err != nil {
		return nil, fmt.Errorf("parsing gem list: %w\noutput was: %s", err, stdout.String())
	}
	return gems, nil
}

func (host *rubyLanguageHost) GetRequiredPackages(
	ctx context.Context, req *pulumirpc.GetRequiredPackagesRequest,
) (*pulumirpc.GetRequiredPackagesResponse, error) {
	if req.Info == nil {
		return nil, errors.New("missing program info")
	}

	gems, err := host.listGems(ctx, req.Info, false /*directOnly*/)
	if err != nil {
		return nil, err
	}

	packages := []*pulumirpc.PackageDependency{}
	for _, gem := range gems {
		if !isPulumiPackage(gem) {
			continue
		}

		pkg, err := packageDependencyFromGem(gem)
		if err != nil {
			return nil, err
		}
		if pkg != nil {
			packages = append(packages, pkg)
		}
	}

	return &pulumirpc.GetRequiredPackagesResponse{Packages: packages}, nil
}

// GetRequiredPlugins is deprecated in favour of GetRequiredPackages, which the engine
// falls back from automatically.
func (host *rubyLanguageHost) GetRequiredPlugins(
	context.Context, *pulumirpc.GetRequiredPluginsRequest,
) (*pulumirpc.GetRequiredPluginsResponse, error) {
	return nil, status.Error(codes.Unimplemented, "GetRequiredPlugins is superseded by GetRequiredPackages")
}

// isPulumiPackage reports whether a gem is a Pulumi package that may need a plugin.
//
// A gem qualifies if it ships a pulumi-plugin.json or is named with the conventional
// prefix. The prefix check mirrors the other SDKs and covers packages generated before
// pulumi-plugin.json became universal.
//
// The core `pulumi` gem is deliberately excluded: it is the SDK, not a resource plugin,
// and it has no pulumi-plugin.json to say otherwise. It still appears in
// GetProgramDependencies, which asks a different question.
func isPulumiPackage(gem gemInfo) bool {
	return gem.PluginJSON != "" || strings.HasPrefix(gem.Name, "pulumi-")
}

// packageDependencyFromGem derives the plugin a gem needs. It returns nil when the gem
// explicitly declares it has no associated resource plugin.
func packageDependencyFromGem(gem gemInfo) (*pulumirpc.PackageDependency, error) {
	var pluginJSON *plugin.PulumiPluginJSON
	if gem.PluginJSON != "" {
		pluginJSON = &plugin.PulumiPluginJSON{}
		if err := json.Unmarshal([]byte(gem.PluginJSON), pluginJSON); err != nil {
			return nil, fmt.Errorf("parsing pulumi-plugin.json for %s: %w", gem.Name, err)
		}
		if !pluginJSON.Resource {
			return nil, nil
		}
	}

	name, version, server := gem.Name, gem.Version, ""
	var parameterization, extension *pulumirpc.PackageParameterization
	if pluginJSON != nil {
		if pluginJSON.Name != "" {
			name = pluginJSON.Name
		}
		if pluginJSON.Version != "" {
			version = pluginJSON.Version
		}
		server = pluginJSON.Server
		parameterization = packageParameterization(pluginJSON.Parameterization)
		extension = packageParameterization(pluginJSON.ExtensionParameterization)
	}

	// Fall back to the gem-name convention, e.g. the `pulumi-aws` gem provides the `aws`
	// plugin. pulumi-plugin.json always wins when it names the plugin explicitly.
	if pluginJSON == nil || pluginJSON.Name == "" {
		name = strings.TrimPrefix(name, "pulumi-")
	}

	return &pulumirpc.PackageDependency{
		Kind:             string(apitype.ResourcePlugin),
		Name:             name,
		Version:          version,
		Server:           server,
		Parameterization: parameterization,
		Extension:        extension,
	}, nil
}

func packageParameterization(p *plugin.PulumiParameterizationJSON) *pulumirpc.PackageParameterization {
	if p == nil {
		return nil
	}
	return &pulumirpc.PackageParameterization{
		Name:    p.Name,
		Version: p.Version,
		Value:   p.Value,
	}
}

func (host *rubyLanguageHost) GetProgramDependencies(
	ctx context.Context, req *pulumirpc.GetProgramDependenciesRequest,
) (*pulumirpc.GetProgramDependenciesResponse, error) {
	if req.Info == nil {
		return nil, errors.New("missing program info")
	}

	gems, err := host.listGems(ctx, req.Info, !req.TransitiveDependencies)
	if err != nil {
		return nil, err
	}

	dependencies := make([]*pulumirpc.DependencyInfo, 0, len(gems))
	for _, gem := range gems {
		dependencies = append(dependencies, &pulumirpc.DependencyInfo{
			Name:    gem.Name,
			Version: gem.Version,
		})
	}

	return &pulumirpc.GetProgramDependenciesResponse{Dependencies: dependencies}, nil
}

func (host *rubyLanguageHost) InstallDependencies(
	req *pulumirpc.InstallDependenciesRequest, server pulumirpc.LanguageRuntime_InstallDependenciesServer,
) error {
	if req.Info == nil {
		return errors.New("missing program info")
	}

	closer, stdout, stderr, err := rpcutil.MakeInstallDependenciesStreams(server, req.IsTerminal)
	if err != nil {
		return err
	}
	defer contract.IgnoreClose(closer)

	tc, err := newToolchain(req.Info.ProgramDirectory, req.Info.RootDirectory)
	if err != nil {
		return err
	}
	if err := tc.validate(); err != nil {
		return err
	}

	// Without a Gemfile there is nothing to install: the program resolves gems straight
	// from the system RubyGems installation. Say so rather than failing, since this is a
	// legitimate (if unusual) way to run a Pulumi program.
	if !tc.usesBundler() {
		_, err := stdout.Write([]byte(
			"No Gemfile found; skipping dependency installation.\n" +
				"Add a Gemfile to have Pulumi manage this program's gems with Bundler.\n\n"))
		if err != nil {
			return err
		}
		return closer.Close()
	}

	if _, err := stdout.Write([]byte("Installing dependencies...\n\n")); err != nil {
		return err
	}

	cmd := tc.bundleCommand(server.Context(), "install")
	cmd.Stdout = stdout
	cmd.Stderr = stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("`bundle install` failed: %w", err)
	}

	if _, err := stdout.Write([]byte("Finished installing dependencies\n\n")); err != nil {
		return err
	}

	return closer.Close()
}
