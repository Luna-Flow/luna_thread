TYPST ?= typst

.PHONY: check-env moon-check native-configure native-build js-install js-build docs docs-en docs-zh

check-env:
	./scripts/check-env.sh

moon-check:
	moon -C luna_thread check

native-configure:
	cmake -S native -B native/build -DLUNA_THREAD_ENABLE_OPENMP=ON

native-build:
	cmake --build native/build

js-install:
	cd js && npm install

js-build:
	cd js && npm run build

docs: docs-en docs-zh

docs-en:
	mkdir -p build/docs
	$(TYPST) compile --root doc/attachments doc/attachments/moonbit_parallel_spec/main.typ build/docs/moonbit_parallel_spec.pdf

docs-zh:
	mkdir -p build/docs
	$(TYPST) compile --root doc/attachments doc/attachments/moonbit_parallel_spec/main.zh_CN.typ build/docs/moonbit_parallel_spec.zh_CN.pdf
