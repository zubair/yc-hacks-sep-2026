# Asset provenance

- `ios/App/Assets.xcassets/DemoPhoto.imageset` is an AI-generated sample travel photograph created for this project. It is bundled only for the credential-free demo; live users choose their own photos.
- `design/screenshots/integration` contains UI-test captures of the integrated app. Older captures in `design/screenshots` predate the final compose screen.
- `packages/PostcardUI/Examples/PreviewApp/coast.jpg` is a demonstration photograph downloaded from Unsplash's image CDN: https://images.unsplash.com/photo-1516483638261-f4dbaf036963?auto=format&fit=crop&w=1200&q=85 . It is used only in the local preview harness, not inserted into user postcards by the UI package. The contributor identity has not been verified, so no photographer attribution is invented.
- The download is covered by the standard Unsplash license: https://unsplash.com/license (checked 2026-09-26). This is a manually bundled demo asset, not an Unsplash API integration.
- Stamp border, seal, layout, colors, and typography composition are original SwiftUI code created for this project.
- System symbols and fonts come from Apple's platform APIs; no external font files or icon packs are bundled.
- Reference PNGs are actual screenshots of the local UI harness with fixture data. They do not prove backend, Duo hardware, or production motion functionality.
