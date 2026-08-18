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

// pulumi-language-ruby is the Pulumi language host for Ruby. It implements the
// pulumirpc.LanguageRuntime service: running Pulumi programs written in Ruby, installing
// their dependencies, and reporting which Pulumi packages they require.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/signal"
	"sync"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/protobuf/types/known/emptypb"

	"github.com/pulumi-labs/pulumi-ruby/pulumi-language-ruby/version"
	"github.com/pulumi/pulumi/sdk/v3/go/common/util/cmdutil"
	"github.com/pulumi/pulumi/sdk/v3/go/common/util/logging"
	"github.com/pulumi/pulumi/sdk/v3/go/common/util/rpcutil"
	pulumirpc "github.com/pulumi/pulumi/sdk/v3/proto/go"
)

// runParams defines the command line arguments accepted by this program.
type runParams struct {
	tracing       string
	engineAddress string
}

func parseRunParams(flag *flag.FlagSet, args []string) (*runParams, error) {
	var p runParams
	flag.StringVar(&p.tracing, "tracing", "", "Emit tracing to a Zipkin-compatible tracing endpoint")

	if err := flag.Parse(args); err != nil {
		return nil, err
	}

	args = flag.Args()
	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, "Warning: launching without arguments, only for debugging")
	} else {
		p.engineAddress = args[0]
	}

	return &p, nil
}

// Launches the language host RPC endpoint.
func main() {
	showVersion := flag.Bool("version", false, "Print the current plugin version and exit")
	p, err := parseRunParams(flag.CommandLine, os.Args[1:])
	if err != nil {
		cmdutil.Exit(err)
	}

	if *showVersion {
		fmt.Println(version.Version)
		os.Exit(0)
	}

	logging.InitLogging(false, 0, false)
	cmdutil.InitTracing("pulumi-language-ruby", "pulumi-language-ruby", p.tracing)

	var cmd mainCmd
	if err := cmd.Run(p); err != nil {
		cmdutil.Exit(err)
	}
}

type mainCmd struct {
	Stdout io.Writer              // == os.Stdout
	Getwd  func() (string, error) // == os.Getwd
}

func (cmd *mainCmd) init() {
	if cmd.Stdout == nil {
		cmd.Stdout = os.Stdout
	}
	if cmd.Getwd == nil {
		cmd.Getwd = os.Getwd
	}
}

func (cmd *mainCmd) Run(p *runParams) error {
	cmd.init()

	cwd, err := cmd.Getwd()
	if err != nil {
		return err
	}

	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt)
	cancelChannel := make(chan bool)
	go func() {
		<-ctx.Done()
		cancel()
		close(cancelChannel)
	}()

	if p.engineAddress != "" {
		if err := rpcutil.Healthcheck(ctx, p.engineAddress, 5*time.Minute, cancel); err != nil {
			return fmt.Errorf("could not start health check host RPC server: %w", err)
		}
	}

	handle, err := rpcutil.ServeWithOptions(rpcutil.ServeOptions{
		Cancel: cancelChannel,
		Init: func(srv *grpc.Server) error {
			pulumirpc.RegisterLanguageRuntimeServer(srv, newLanguageHost(p.engineAddress, cwd, p.tracing))
			return nil
		},
		Options: rpcutil.OpenTracingServerInterceptorOptions(nil),
	})
	if err != nil {
		return fmt.Errorf("could not start language host RPC server: %w", err)
	}

	// The engine reads the port from stdout, so a failure to write it is fatal rather
	// than cosmetic: the plugin would serve forever with nobody able to reach it.
	if _, err := fmt.Fprintf(cmd.Stdout, "%d\n", handle.Port); err != nil {
		return fmt.Errorf("could not report the port to the engine: %w", err)
	}

	if err := <-handle.Done; err != nil {
		return fmt.Errorf("language host RPC stopped serving: %w", err)
	}

	return nil
}

// Embedding UnsafeLanguageRuntimeServer opts out of gRPC's forward-compatibility struct,
// which would otherwise silently supply stubs for methods we forgot. This assertion is
// what makes "implements every RPC" a compile-time property instead of a runtime surprise
// the first time the engine calls the missing one.
var _ pulumirpc.LanguageRuntimeServer = (*rubyLanguageHost)(nil)

// rubyLanguageHost implements pulumirpc.LanguageRuntimeServer.
type rubyLanguageHost struct {
	pulumirpc.UnsafeLanguageRuntimeServer

	cwd     string
	tracing string

	// engineAddress is set by Handshake and read by Run, which arrive on different gRPC
	// goroutines.
	mu            sync.Mutex
	engineAddress string

	// cancelCtx is cancelled by the Cancel RPC, which is how the engine asks a running
	// program to wind down. Run derives the child process's context from it.
	cancelCtx  context.Context
	cancelFunc context.CancelFunc
}

func newLanguageHost(engineAddress, cwd, tracing string) pulumirpc.LanguageRuntimeServer {
	cancelCtx, cancelFunc := context.WithCancel(context.Background())
	return &rubyLanguageHost{
		engineAddress: engineAddress,
		cwd:           cwd,
		tracing:       tracing,
		cancelCtx:     cancelCtx,
		cancelFunc:    cancelFunc,
	}
}

func (host *rubyLanguageHost) Handshake(
	_ context.Context,
	req *pulumirpc.LanguageHandshakeRequest,
) (*pulumirpc.LanguageHandshakeResponse, error) {
	if req == nil || req.EngineAddress == "" {
		return nil, errors.New("request must contain the engine address")
	}
	host.setEngineAddress(req.EngineAddress)

	// Deliberately not derived from the request context: the health check has to outlive
	// this RPC. Rooting it here would tear the monitor down the moment Handshake returned,
	// so the host would never notice the engine going away and would linger forever.
	ctx, cancel := context.WithCancel(context.Background())
	if err := rpcutil.Healthcheck(ctx, req.EngineAddress, 5*time.Minute, cancel); err != nil {
		cancel()
		return nil, fmt.Errorf("could not start health check host RPC server: %w", err)
	}

	return &pulumirpc.LanguageHandshakeResponse{}, nil
}

func (host *rubyLanguageHost) setEngineAddress(address string) {
	host.mu.Lock()
	defer host.mu.Unlock()
	host.engineAddress = address
}

func (host *rubyLanguageHost) getEngineAddress() string {
	host.mu.Lock()
	defer host.mu.Unlock()
	return host.engineAddress
}

func (host *rubyLanguageHost) GetPluginInfo(context.Context, *emptypb.Empty) (*pulumirpc.PluginInfo, error) {
	return &pulumirpc.PluginInfo{Version: version.Version}, nil
}

func (host *rubyLanguageHost) Cancel(context.Context, *emptypb.Empty) (*emptypb.Empty, error) {
	host.cancelFunc()
	return &emptypb.Empty{}, nil
}
