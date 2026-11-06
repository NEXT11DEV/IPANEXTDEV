# SkinMenu integrated trial — integrated prototype

This source revision addresses the user's request for Skins inside the original Ninja menu. The user approved publishing this source to the public build repository. Compilation and packaging are in progress; no iPhone runtime verification has been performed.

## What changed

- Removes the separate purple button. A transparent UIKit view follows the verified original menu rectangle, replacing its four-tab header with ESP / AutoPlay / Queue / Skins / Account. The other tabs continue to select their original native menu content. The original close button remains uncovered.
- Adds a Skins content pane: seven star images, level slider, Cue / Frame / Avatar sections, image tiles, Off, restore, and a diagnostic report action.
- Adds the two in-match HUD star selectors found in the user's current report. The prior trial only changed the pre-match widget.
- Removes the prior requirement that rendering hooks run on the UIKit main thread. Preferences use atomics, caches use a lock, and visual refresh happens through CCDirector drawScene.
- Identifies the local player by comparing the existing in-memory account identifier against the player slot, without logging/storing identifiers. Unidentified/opponent slots pass through.
- Adds local avatar-frame and ordinary avatar rendering hooks. It does not implement animated-avatar products or table appearance.
- Observes the IDs of items actually rendered by the game. On the rendering thread, it attempts to capture their Cocos nodes into thumbnails via CCRenderTexture. This capture path is UNTESTED. The image catalog fills from observed items; it is not the donor's complete catalog.
- Keeps ActivationAccessActive as the access gate. The new report records access state, renderer call counts, render-thread status, local-HUD identification, and the verified-engine result, with no keys/tokens/user identifiers.

## Verification boundary

The user's SkinLab report confirmed that all four previous hook implementations were installed. It did not record call counts, access state, or thread execution. The previous star hook targeted MatchScreenPlayerWidget, so it did not implement the live HUD shown in the reference.

The new source uses the method names/signatures from the report and verifies signatures again before installation. Original methods are retained. The integrated menu adapter is restricted to the exact Ninja UUID from the supplied working IPA; offsets must not be reused for another engine build.

The supplied working IPA and all its existing engine/ActivationKit bytes are retained by the packaging script. Only an additional framework dependency is added to the main Mach-O header. Re-signing is required. The package is created separately and never overwrites the input.

## Build and assets

On a Mac with Xcode: `bash build.sh`. The intended GitHub Actions workflow is included as workflow.yml. The user explicitly approved publishing this derived source in the public NEXT11DEV/IPANEXTDEV repository.

`package_menu.py` expects the compiled artifact at output/SkinMenu-unsigned.zip, the two original user-attached IPAs under upload/, and copies 11 existing menu/star images from the donor into the new framework privately. No game IPA or image assets are intended for the public repository.

A successful compile and ZIP check would still not prove runtime behavior. The integrated menu, in-match identification, Cocos capture, frame selection, avatar selection, and cue appearance must all be validated on the iPhone before calling this a working port.
