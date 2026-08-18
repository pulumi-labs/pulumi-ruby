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
	"fmt"
	"strings"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/hashicorp/hcl/v2"
	"github.com/pulumi-labs/pulumi-ruby/pulumi-language-ruby/codegen"
	hclsyntax "github.com/pulumi/pulumi/pkg/v3/codegen/hcl2/syntax"
	"github.com/pulumi/pulumi/pkg/v3/codegen/pcl"
	"github.com/pulumi/pulumi/pkg/v3/codegen/schema"
	"github.com/pulumi/pulumi/sdk/v3/go/common/resource/plugin"
	"github.com/pulumi/pulumi/sdk/v3/go/common/util/contract"
	"github.com/pulumi/pulumi/sdk/v3/go/common/workspace"
	pulumirpc "github.com/pulumi/pulumi/sdk/v3/proto/go"
)

// bindProgram loads and type-checks the PCL in a directory.
func bindProgram(directory, loaderTarget string, strict bool) (*pcl.Program, hcl.Diagnostics, error) {
	client, err := schema.NewLoaderClient(loaderTarget)
	if err != nil {
		return nil, nil, err
	}
	defer contract.IgnoreClose(client)

	options := []pcl.BindOption{pcl.PreferOutputVersionedInvokes}
	if !strict {
		options = append(options, pcl.NonStrictBindOptions()...)
	}

	return pcl.BindDirectory(directory, schema.NewCachedLoader(client), options...)
}

func (host *rubyLanguageHost) GenerateProgram(
	_ context.Context, req *pulumirpc.GenerateProgramRequest,
) (*pulumirpc.GenerateProgramResponse, error) {
	loader, err := schema.NewLoaderClient(req.LoaderTarget)
	if err != nil {
		return nil, err
	}
	defer contract.IgnoreClose(loader)

	parser := hclsyntax.NewParser()
	for name, contents := range req.Source {
		if err := parser.ParseFile(strings.NewReader(contents), name); err != nil {
			return nil, err
		}
	}
	if diagnostics := parser.Diagnostics; diagnostics.HasErrors() {
		return &pulumirpc.GenerateProgramResponse{
			Diagnostics: plugin.HclDiagnosticsToRPCDiagnostics(diagnostics),
		}, nil
	}

	options := []pcl.BindOption{pcl.PreferOutputVersionedInvokes}
	if !req.Strict {
		options = append(options, pcl.NonStrictBindOptions()...)
	}

	program, diagnostics, err := pcl.BindProgram(parser.Files, schema.NewCachedLoader(loader), options...)
	if err != nil {
		return nil, err
	}
	if diagnostics.HasErrors() || program == nil {
		return &pulumirpc.GenerateProgramResponse{Diagnostics: plugin.HclDiagnosticsToRPCDiagnostics(diagnostics)}, nil
	}

	files, genDiagnostics, err := codegen.GenerateProgram(program)
	if err != nil {
		return nil, err
	}
	diagnostics = diagnostics.Extend(genDiagnostics)

	return &pulumirpc.GenerateProgramResponse{
		Source:      files,
		Diagnostics: plugin.HclDiagnosticsToRPCDiagnostics(diagnostics),
	}, nil
}

func (host *rubyLanguageHost) GenerateProject(
	_ context.Context, req *pulumirpc.GenerateProjectRequest,
) (*pulumirpc.GenerateProjectResponse, error) {
	program, diagnostics, err := bindProgram(req.SourceDirectory, req.LoaderTarget, req.Strict)
	if err != nil {
		return nil, err
	}
	if diagnostics.HasErrors() || program == nil {
		return &pulumirpc.GenerateProjectResponse{Diagnostics: plugin.HclDiagnosticsToRPCDiagnostics(diagnostics)}, nil
	}

	var project workspace.Project
	if err := json.Unmarshal([]byte(req.Project), &project); err != nil {
		return nil, fmt.Errorf("parsing project: %w", err)
	}

	if err := codegen.GenerateProject(
		req.TargetDirectory, project, program, req.LocalDependencies,
	); err != nil {
		return nil, err
	}

	return &pulumirpc.GenerateProjectResponse{Diagnostics: plugin.HclDiagnosticsToRPCDiagnostics(diagnostics)}, nil
}

// GeneratePackage generates a Ruby SDK ("sdkgen") from a package schema.
//
// Not implemented yet, so providers are reached through their type token instead. Reported
// as Unimplemented rather than stubbed with an empty response so the engine and the
// conformance harness can detect the gap rather than silently produce an empty gem.
func (host *rubyLanguageHost) GeneratePackage(
	context.Context, *pulumirpc.GeneratePackageRequest,
) (*pulumirpc.GeneratePackageResponse, error) {
	return nil, status.Error(codes.Unimplemented,
		"Ruby SDK generation is not implemented yet; see https://github.com/pulumi-labs/pulumi-ruby")
}
