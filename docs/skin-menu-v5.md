# Revision 5 — performance and activation safeguards

The user's SkinMenu-4 report showed active access, level enabled, lobbyCalls=0, localHUDIdentified=false and cueAppearanceApplied=0. The uploaded screenshot/report also had cue selection Off (-1).

Performance changes remove continuous retained-node image queues and repeated 5000-node searches from the render path. Scene discovery is now user-requested and incremental (24 nodes per frame, 768 total), and supports both TopBarUserProfileButton and TopBarTrophyButton. Thumbnails are optional, low-rate, and paused while a tracked gameplay cue/HUD exists. Menu geometry is no longer laid out unconditionally at every clock tick. Diagnostics separate the worst observed extension overhead from the underlying draw time. This is not a measured on-device performance claim.

Activation protection adds startup SHA-256 verification of the existing ActivationKit __text section and validates that the activation-status function address is inside that verified section. The hash excludes signatures so ordinary re-signing is compatible. Cosmetic access and three native feature entrypoints (AutoPlay.Update, TickAutoQueue, DrawESP) require the exported SkinFeatureAccess function. Missing verification, inactive server session, or missing SkinMenu export prevents those feature functions from running. Removing a UI window alone does not grant feature access. The existing activation server and keychain session are retained.

This is not tamper-proof. An attacker capable of rewriting the client binary can still patch guards. There is no hardware attestation or newly signed server lease in this revision. The client relies on the existing server-validated activation session, expiry, revocation, and device binding.

The packaging script adds guards only after verifying the existing original prologue instructions and zero padding. It preserves the app executable, ActivationKit binary, other frameworks and image assets. All modified frameworks must be re-signed. Native guard branches and framework exports must be checked after compilation. No iPhone runtime test is represented by a successful CI build or ZIP check.

The full donor skin catalog and animated-avatar products remain outside this independent trial. Visual operation is still experimental; this revision prioritizes removing likely extension-side stutters and strengthening activation enforcement. Developer links from revision 4 remain unchanged.
