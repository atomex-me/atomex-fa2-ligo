.PHONY: build test

build:
	scripts/build.sh

test:
	pytest . -v

#install:
#	pytezos deploy src/atomex.tz --dry_run
