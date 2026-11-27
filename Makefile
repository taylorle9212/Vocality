.PHONY: build app run clean validate

# Debug build of the executable.
build:
	swift build

# Release build wrapped in a signed Vocality.app, copied to ~/Downloads.
app:
	./scripts/bundle.sh

run: app
	open ~/Downloads/Vocality.app

clean:
	rm -rf .build build

validate:
	./scripts/validate.sh
