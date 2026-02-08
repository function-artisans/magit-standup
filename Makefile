.PHONY: lint test clean

.deps: Easkfile
	eask install-deps
	@touch .deps

.compile: .deps magit-standup.el
	eask compile
	@touch .compile

lint: .deps
	eask lint package

test: .compile
	eask test buttercup

clean:
	eask clean all
	@rm -f .deps .compile
