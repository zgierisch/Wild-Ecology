# Local Sprite Assets

Wild Ecology does not distribute Pokémon overworld sprite artwork. The
project does not grant or claim a license for third-party Pokémon assets.

## Importing local art

Provide an already-extracted directory of compatible overworld sheets, then
run the offline importer from the repository root:

```text
python tools/build_ow_sprites.py <path-to-extracted-sprite-sheets>
```

The importer reads numbered PNG sheets such as `001.png` through `151.png`.
It expects the source sheets to use a 4x4, 64-pixel-cell walk-cycle layout
with rows ordered down, left, right, up. It writes normalized 16x96 walker
sheets to `generated-assets/ow_sprites/`.

The source directory may be anywhere on the local machine. An extracted copy
can also be placed under `external-assets/`; both `external-assets/` and
`generated-assets/` are ignored by Git. Local `.7z` archives are ignored at
the repository root as well. The importer never downloads an archive or
contacts a network service.

## Runtime behavior

At startup, Wild Ecology looks for generated files under
`generated-assets/ow_sprites/`. A species with an available generated walker
sheet uses it. If the file is absent, registration falls back to the host
Pokémon record's `spriteFront` when available; otherwise the normal generic
sprite fallback remains in effect. Generation diagnostics identify how many
walker sheets were found and how many species used the fallback.

Missing required Gen I sheets cause the importer to report their numbered
filenames and return a failure status. No image data, base64 encoding, or
generated output is committed to the repository.