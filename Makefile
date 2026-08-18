GO_TEST_FILTER_FLAG := $(if $(TEST_FILTER),-run 'TestLanguage/$(TEST_FILTER)$$',-run TestLanguage)

# The module path the version symbol lives under. It has to match
# pulumi-language-ruby/go.mod exactly: the linker ignores a -X whose symbol it cannot
# resolve, silently producing an unstamped binary. Update both together if the repository
# moves.
VERSION_PKG := github.com/pulumi-labs/pulumi-ruby/pulumi-language-ruby/version

# An unreleased build stamps a dev version derived from the pending changelog, so a locally
# built host reports something more useful than an empty string. changie is optional;
# without it the fallback keeps the build working, and it claims 0.0.0 rather than a
# specific release so it cannot drift into asserting a version that has actually shipped.
FALLBACK_DEV_VERSION := 0.0.0-dev.0
DEV_VERSION := $(shell if command -v changie > /dev/null 2>&1; then changie next patch -p dev.0 | sed 's/^v//'; else echo "$(FALLBACK_DEV_VERSION)"; fi)
LD_FLAGS := -X $(VERSION_PKG).Version=$(DEV_VERSION)

RUBY_SDK      := sdk/ruby
LANGUAGE_HOST := pulumi-language-ruby

.PHONY: build build_sdk build_language_host install_plugin test_sdk test_types \
	test_language_host test_conformance test_fast test_all accept lint lint_go lint_ruby \
	format changelog gem protos clean

build: build_sdk build_language_host

# The gem needs no compilation; installing its dependencies is the equivalent step, and it
# is what the specs and the type check both require.
build_sdk:
	cd $(RUBY_SDK) && bundle install

build_language_host:
	cd $(LANGUAGE_HOST) && go build -ldflags "$(LD_FLAGS)" .

# Puts the host where the CLI looks for it, so `runtime: ruby` resolves without this
# repository's build output being on PATH.
install_plugin: build_language_host
	cp $(LANGUAGE_HOST)/pulumi-language-ruby "$(HOME)/.pulumi/bin/"

test_sdk:
	cd $(RUBY_SDK) && bundle exec rspec

# RBS validation plus a Steep check of a sample program. The signatures exist for user
# programs, so a program is what is checked.
test_types:
	cd $(RUBY_SDK) && bundle exec rake types

test_language_host:
	cd $(LANGUAGE_HOST) && go test -run 'Test[^L]' ./...

test_conformance: build
	cd $(LANGUAGE_HOST) && go test $(GO_TEST_FILTER_FLAG) -timeout 120m .

# Everything that needs neither a network nor a provider plugin. The set to run before
# pushing.
test_fast: test_sdk test_types test_language_host

test_all: test_fast test_conformance

# Regenerate conformance snapshots (testdata/) after codegen changes.
accept: build
	cd $(LANGUAGE_HOST) && PULUMI_ACCEPT=1 go test $(GO_TEST_FILTER_FLAG) -timeout 120m .

lint: lint_go lint_ruby

# golangci-lint has to run from inside the module: there is no go.mod at the repository
# root, so a ./pulumi-language-ruby/... pattern from here resolves to nothing and the
# linter exits without having linted anything.
lint_go:
	cd $(LANGUAGE_HOST) && go vet ./...
	cd $(LANGUAGE_HOST) && golangci-lint run --config ../.golangci.yml ./...
	cd $(LANGUAGE_HOST) && go mod tidy -diff

lint_ruby:
	cd $(RUBY_SDK) && bundle exec rubocop

format:
	cd $(RUBY_SDK) && bundle exec rubocop --autocorrect
	cd $(LANGUAGE_HOST) && golangci-lint fmt --config ../.golangci.yml ./...

changelog:
	changie new

gem:
	cd $(RUBY_SDK) && gem build pulumi.gemspec

# Regenerates the gRPC bindings from a pinned pulumi/pulumi ref. Set USE_SIBLING=1 to pull
# from a checkout next to this one when iterating on the protocol locally.
protos:
	scripts/sync-protos.sh

clean:
	rm -f $(LANGUAGE_HOST)/pulumi-language-ruby
	rm -rf bin $(RUBY_SDK)/*.gem $(RUBY_SDK)/.bundle $(RUBY_SDK)/.steep
