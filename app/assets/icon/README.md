# App icon

An original cat reviewing a diff: glasses with a red **−** lens and a green **+** lens.
It is not the Octocat, because GitHub's logo policy doesn't allow that in app icons.

| File | Used for |
|---|---|
| `icon.svg` / `.png` | iOS, legacy Android, README (full-bleed square; platforms apply their own mask) |
| `foreground.*` / `background.*` | Android adaptive icon (art sits inside the 66dp safe circle) |
| `monochrome.*` | Android 13+ themed icon (shape carried by alpha) |

The SVGs are the source, written by `generate_svgs.py`. To change the icon:

```bash
python3 assets/icon/generate_svgs.py assets/icon      # from app/: rewrite the SVGs
# Render each SVG to a 1024×1024 PNG with the same name (any SVG renderer;
# headless Chrome: --headless --screenshot --window-size=1024,1024 --default-background-color=00000000)
dart run flutter_launcher_icons                        # from app/: regenerate every platform size
```

`flutter_launcher_icons` 0.14 rewrites `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS` in
`ios/Runner.xcodeproj/project.pbxproj` to `AppIcon`. Revert that line. It must stay `YES`.
