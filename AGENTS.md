# Usage Rings

Personal macOS usage monitor, extracted from Context. Keep the four providers and
WidgetKit extension independent of Context. Local distribution packaging is allowed.
Keep initial GitHub releases as drafts; public publishing requires explicit approval.

- `Sources/UsageRings`: background app, local session readers, polling and detail window.
- `Sources/UsageCore`: shared models, parsers, ring views and icons.
- `Sources/UsageRingsWidget`: WidgetKit extension and sanitized snapshot cache.
- Validation: `make check`, then `make build` for embedded bundle/signing checks.
- Distribution: `make package-unnotarized` for explicitly unnotarized DMG/ZIP releases;
  `make package-draft` for review ZIPs. Optional `make package` requires Developer ID
  signatures, hardened runtime, and notarization. Never remove quarantine or disable
  system security in installation scripts.
- Installation/update for this Mac: `make install`.
- Never log, commit, or copy login credentials into the project or widget.
