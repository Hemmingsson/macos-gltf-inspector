# Project tools

These tools generate documentation and README media. They are kept separate from
the shipped application and from the generated files in `assets/`.

| Path | Purpose |
| --- | --- |
| `tools/readme/` | Capture the app window and compose the README screenshots and Finder mockups. |
| `tools/docs/` | Source specs and generators for the architecture and design diagrams. |
| `assets/` | Shipped artwork and generated documentation media. |
| `docs/` | Written product, architecture, development, and usage documentation. |

Generated files should be written to `assets/` or `.build/`, not back into `tools/`.
