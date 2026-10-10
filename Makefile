# Thin wrappers over scripts/. The scripts are the source of truth.
.PHONY: build test run install package eval clean

build:
	swift build

test:
	scripts/test.sh

run:
	scripts/run.sh

install:
	scripts/install.sh

package:
	scripts/package.sh

eval: build
	.build/debug/hark --eval evals/developer-day.json

clean:
	rm -rf .build build
