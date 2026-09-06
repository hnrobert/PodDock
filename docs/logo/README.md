# PodDock logo assets

A dot docking into a tray — a DNS record landing in the dock's empty slot.
Minimal tech mark: pure geometry, no text, readable down to 16 px.
Single theme: pale mint tile with a dark tray.

## Files

| File | Use |
| --- | --- |
| `poddock-logo.svg` | Tile icon (light theme) — embedded directly in the README |
| `poddock-mark.svg` | Bare mark, no tile, no text (transparent background) |

No PNGs are committed. The README embeds the SVG directly, and all PNG
exports are generated on demand:

```bash
# App icons (iOS single-size 1024 + macOS 16–1024, real alpha)
# CI runs this before every build; run it once locally before first build.
swift scripts/generate-app-icons.swift

# Docs icon/mark exports (macOS, qlmanage)
cd docs/logo
for size in 1024 512 256 128 64 32; do
  qlmanage -t -s $size poddock-logo.svg -o . >/dev/null 2>&1
  mv poddock-logo.svg.png poddock-icon-$size.png
  qlmanage -t -s $size poddock-mark.svg -o . >/dev/null 2>&1
  mv poddock-mark.svg.png poddock-mark-$size.png
done
```

## Palette

Theme green follows Apple system green — the same color as the app accent
(`AccentColor` light `#34C759` / dark `#30D158`) and the `.green` used in views.

| Token | Hex | Role |
| --- | --- | --- |
| Tile | `#f2fbf4 → #d7f0dd` | Pale mint gradient |
| Glow | `#34C759 @ 18% → 0` | Center radial glow |
| Tray | `#10231a` | Dark tray |
| Dot | `#30D158 → #21823C` | System-green gradient dots |
| Beam | `#34C759 @ 45% → 0` | Docking trajectory |

## Design notes

- macOS icons keep the squircle shape and transparent margins in the asset;
  iOS uses a full-bleed square because the system masks the corners.
- The Xcode 16 single-size 1024 slot rejects alpha on macOS, so the mac icon
  uses the traditional multi-size slots (16–1024) to keep its shape.

Licensing: see [ATTRIBUTION.md](ATTRIBUTION.md) — all geometry original.
