---
name: compose-app-icon
description: Create, edit, and validate Apple Icon Composer .icon packages, including appearance variants and Liquid Glass settings.
license: Apache-2.0
---

# Apple Icon Composer packages

The app's icon package is `assets/ICON.icon`. It contains `icon.json` and an `Assets/` directory. The package is included by `project.yml` as the `GLTFInspector` app's resource and its `CFBundleIconName` is `ICON`.

The bundled `scripts/` directory is a self-contained `uv` project. Run `which uv` first; if it is unavailable, stop. Then run commands from `.agents/skills/compose-app-icon/scripts/`:

```sh
uv sync
uv run python create_icon.py --output /tmp/Example.icon --icon /tmp/icon.json --asset symbol.png=/path/to/symbol.png
uv run python validate_icon.py ../../../../assets/ICON.icon
```

`create_icon.py` validates `icon.json`, checks every referenced `image-name` has an `--asset`, copies assets into `Assets/`, and writes a `.icon` package. `validate_icon.py` checks the bundled JSON Schema and, for a package, checks referenced files in `Assets/`. Exit code 0 is valid, 1 is a schema or asset error, and 2 is a bad input path.

For an existing icon, edit only `assets/ICON.icon/icon.json` or a file in its `Assets/` directory, then validate the whole package. Keep asset filenames synchronized with `image-name` and `image-name-specializations.value`. `position` requires both `scale` and `translation-in-points`; omit it for the identity transform.

Icon Composer 2 documents must declare `features` when using `refractivity` or `specular-highlight-placement`. Group `shadow`, `translucency`, and `refractivity` specializations replace the whole object. Use the schema and the existing `assets/ICON.icon/icon.json` as the repository-specific examples.

On macOS with Xcode's Icon Composer tool available, render a rendition with `ictool` after schema validation to catch loader-level errors. Inspect the resulting PNG. Do not replace the checked-in icon package with generated output without checking the app icon in the built app.
