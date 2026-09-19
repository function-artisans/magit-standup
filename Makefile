.PHONY: lint test clean release

.deps: Easkfile
	eask install-deps
	@touch .deps

.compile: .deps magit-standup.el
	eask compile
	@touch .compile

lint: .deps
	eask lint package
	eask lint checkdoc

test: .compile
	eask test buttercup

clean:
	eask clean all
	@rm -f .deps .compile

release: lint test
	@test -n "$(VERSION)" || { echo "Give the version: make release VERSION=x.y.z"; exit 1; }
	@git diff --quiet HEAD || { echo "Commit your changes first."; exit 1; }
	git switch -c release/v$(VERSION)
	sed 's/^;; Version: .*/;; Version: $(VERSION)/' magit-standup.el > magit-standup.el.new
	mv magit-standup.el.new magit-standup.el
	sed '2s/"[0-9][0-9.]*"/"$(VERSION)"/' Easkfile > Easkfile.new
	mv Easkfile.new Easkfile
	@grep -qx ";; Version: $(VERSION)" magit-standup.el
	@grep -qx '         "$(VERSION)"' Easkfile
	git commit -am "Bump the version to $(VERSION)"
	@echo
	@echo "Next:"
	@echo "  git push -u origin release/v$(VERSION)"
	@echo "  gh pr create --fill --label release"
	@echo "Merge it, and the workflow makes the tag and the release."
