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

## Revision 3

The user's SkinMenu-2 report confirmed active access, a matching engine, working draw callbacks, and all original hook entrypoints being called. It also showed localHUDIdentified=false. Their screenshots demonstrated that the lobby profile star was not covered by the existing hooks.

Revision 3 adds TopBarUserProfileButton.updateUserLeagueStarForLeague:withLevel:, so the local lobby profile can be refreshed on the render thread. In-match identification now asks the game's GameHUD.isPlayer1:/isPlayer2: using GameManager.player, instead of relying solely on identifier-string equality.

Cue appearance now substitutes an already-observed CueWidget sprite-definition object through setupWithCueSpriteDefinition:productId:cueLevel:forceSpriteDef:, preserving the original product ID and cue level. Own/opponent render scope is tracked so an opponent render clears the local cue marker. The catalog still contains observed definitions only; a gallery with a single current cue does not supply a different appearance.

The menu's UIKit layout is forced left-to-right to match the reference's star/slider/tab order. The existing Telegram icon on the activation screen and a developer button inside the original Account tab open https://t.me/YG8_1. The developer button is not inside Skins. Additional diagnostic fields show lobby/definition hook installation and appearance-application counts. Revision 3 has not yet been tested on an iPhone.

Revision 3 also marks the lobby profile avatar through its verified _playerAvatar object ivar, so local avatar/frame refresh can cover the lobby. It skips cue refresh while the opponent cue is active. ActivationKit API origin and framework bytes remain unchanged: only the Telegram control target is rewired at runtime.

## Revision 4: account layout and link routing

The user's new account screenshot showed the separate developer pill overlapping the countdown and the original tab underline showing through below the replacement header. Revision 4 removes that pill entirely, increases header coverage to mask the underlying underline, and uses the original account controls. For the verified Ninja UUID only, the existing social Telegram and support/resellership std::string values are assigned the user-provided https://t.me/YG8_1 URL using the same in-image string assignment routine already used by the activation username bridge. Re-selecting Account schedules reconfiguration. Both the activation panel's existing Telegram and Official Resellers controls are wired to the developer link. No account overlay button is added.

The supplied SkinMenu-3 report showed lobbyCalls=0 and cueAppearanceApplied=0 despite active access. Revision 4 searches the already-running Cocos scene for a pre-existing TopBarUserProfileButton, then invokes its original local updateUserInfo path to initialize the hook's view references. It does not create GameManager solely for discovery. It also intercepts the final CueWidget.setupWithCueSpriteDefinition:productId:forceSpriteDef: overload and retains the observed local cue widget, allowing refresh to update its sprite definition directly instead of relying on a potentially short-circuited same-cue setter. These fixes still require on-device validation.

The 109.1-second attached reference video was reviewed through its timeline frames. It shows a pre-populated cue/frame gallery and selections within the menu. The 56.34.0 build 5354 donor differs from the prior 56.33.0 build 5346 engine; the primary code section and companion library differ. No additional readable UI feature phrases were established by the string comparison. The new donor is kept as a reference rather than replacing the working game's engine. The complete pre-populated gallery remains unimplemented in this independent trial.
