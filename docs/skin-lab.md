# SkinLab cosmetic trial

An independent first cosmetic prototype for the user-provided ActivationKit IPA, based on method names/signatures observed in the on-device SkinProbe report. It does not transplant the donor engine.

Features: local player's pre-match star color and displayed level; an experimental cue appearance override using only cue IDs observed by existing renderer calls. The overlay has restore-original and diagnostic-export actions. The game menu, table appearance, avatar frame, animated avatar and actual account data are not modified by this trial. Cue choice uses numeric IDs rather than a finished image gallery. At most 40 observed cue IDs appear per menu.

The library checks Objective-C method signatures before replacing four rendering/factory methods. It does not call UserInfo setters, change entitlement/ownership checks, or change the original physics/power values. Opponent cue rendering passes through. Star changes are restricted to widgets constructed by createLocalPlayerWidget; the live match HUD is not changed by the star hook. The existing ActivationAccessActive check gates the cosmetic override when it is present. On an app without that export, Access returns true; this build is packaged only with the existing ActivationKit app.

The source defaults to visual changes disabled. Open the purple `Skins تجربة` menu. Enable star/level appearance and choose values, then enter a match to rebuild the local pre-match widget. For cue choices, view cues in the game's shop, reopen the menu, and choose an observed numeric cue ID. The selected cue override is not persisted across launches. Star preferences are local user defaults. The restore action returns tracked renderers to their original arguments where possible.

No iPhone runtime verification of this trial has been performed by the builder. A successful compile/ZIP check does not demonstrate cosmetic behavior or stability. If a hook signature does not match, that hook is not installed. The diagnostic report records metadata only and does not capture keys/tokens/user identifiers. Share SkinLab-report.json if the trial does not work.

The private IPA packaging preserves existing frameworks byte-for-byte, adds SkinLab.framework, and changes only the main Mach-O load-command header. Full re-signing is required. Original files are not overwritten.
