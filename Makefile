# Copyright Splunk Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

MODULE           = $(shell $(GO) list -m)
TOOLS_MODULE_DIR = $(CURDIR)/internal/tools
TEST_RESULTS     = $(CURDIR)/test-results

PKGS     = $(or $(PKG),$(shell $(GO) list ./...))
TESTPKGS = $(shell $(GO) list -f '{{ if or .TestGoFiles .XTestGoFiles }}{{ .ImportPath }}{{ end }}' $(PKGS))

GO = go
TIMEOUT = 15

# Verbose output
V = 0
Q = $(if $(filter 1,$V),,@)

.DEFAULT_GOAL := all

.PHONY: all
all: imports lint staticcheck misspell license-check
	$Q $(GO) build $(PKGS)
# Compile all test code.
	$Q $(GO) test -vet=off -run xxxxxMatchNothingxxxxx $(TESTPKGS) >/dev/null

# Tools

TOOLS = $(CURDIR)/.tools

$(TOOLS):
	@mkdir -p $@
$(TOOLS)/%: | $(TOOLS)
	$Q cd $(TOOLS_MODULE_DIR) \
		&& $(GO) build -o $@ $(PACKAGE)

GOLINT = $(TOOLS)/golint
$(TOOLS)/golint: PACKAGE=golang.org/x/lint/golint

GOIMPORTS = $(TOOLS)/goimports
$(TOOLS)/goimports: PACKAGE=golang.org/x/tools/cmd/goimports

MISSPELL = $(TOOLS)/misspell
$(TOOLS)/misspell: PACKAGE=github.com/client9/misspell/cmd/misspell

STATICCHECK = $(TOOLS)/staticcheck
$(TOOLS)/staticcheck: PACKAGE=honnef.co/go/tools/cmd/staticcheck

# Tests

TEST_TARGETS := test-bench test-short test-verbose test-race
.PHONY: $(TEST_TARGETS) test tests
test-bench:   ARGS=-run=xxxxxMatchNothingxxxxx -test.benchtime=1ms -bench=.
test-short:   ARGS=-short
test-verbose: ARGS=-v
test-race:    ARGS=-race
$(TEST_TARGETS): test
test tests:
	$Q $(GO) test -timeout $(TIMEOUT)s $(ARGS) $(TESTPKGS)

COVERAGE_MODE    = atomic
COVERAGE_PROFILE = $(COVERAGE_DIR)/profile.out
.PHONY: test-coverage
test-coverage: COVERAGE_DIR := $(TEST_RESULTS)/coverage_$(shell date -u +"%s")
test-coverage:
	$Q mkdir -p $(COVERAGE_DIR)
	$Q $(GO) test \
		-coverpkg=$$($(GO) list -f '{{ join .Deps "\n" }}' $(TESTPKGS) | \
					grep '^$(MODULE)/' | \
					tr '\n' ',' | sed 's/,$$//') \
		-covermode=$(COVERAGE_MODE) \
		-coverprofile="$(COVERAGE_PROFILE)" $(TESTPKGS)

.PHONY: lint
lint: | $(GOLINT)
	$Q $(GOLINT) -set_exit_status $(PKGS)

.PHONY: fmt imports
fmt imports: | $(GOIMPORTS)
	$Q $(GOIMPORTS) -w .

.PHONY: misspell
misspell: | $(MISSPELL)
	$Q $(MISSPELL) -w $(shell find . -name '*.md' -type f | sort)

.PHONY: staticcheck
staticcheck: | $(STATICCHECK)
	$Q $(STATICCHECK) $(PKGS)

.PHONY: license-check
license-check:
	$Q licRes=$$(for f in $$(find . -type f \( -iname '*.go' -o -iname '*.sh' -o -iname '*.yml' \)) ; do \
	           awk '/Copyright Splunk Inc.|generated|GENERATED/ && NR<=3 { found=1; next } END { if (!found) print FILENAME }' $$f; \
	   done); \
	   if [ -n "$${licRes}" ]; then \
	           echo "license header checking failed:"; echo "$${licRes}"; \
	           exit 1; \
	   fi
