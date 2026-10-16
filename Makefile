.PHONY: build check run install package package-draft package-unnotarized site-check site-build site-dev
build:
	./script/build.sh
check:
	./script/check.sh
run: build
	open "dist/Usage Rings.app"
install:
	./script/install.sh
package:
	python3 ./script/package.py
package-draft:
	python3 ./script/package.py --draft
package-unnotarized:
	python3 ./script/package.py --unnotarized
site-check:
	cd site && bun run check
site-build:
	cd site && bun run build
site-dev:
	cd site && bun run dev
