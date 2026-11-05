# ActivationKit — native iOS prototype

Own-source Objective-C activation/account UI using the deployed activation API. No game binary, IPA, passwords, signing keys or server administration credentials are included.

## Build

Run `bash build.sh` on macOS with Xcode, or trigger the included GitHub Actions workflow on a standard macOS runner. Check the account's included usage before using a private repository. The workflow is capped at ten minutes; artifacts are kept for one day. No paid/larger runner is selected.

## Status

Source prepared only: NOT COMPILED and NOT DEVICE TESTED. This is not a connected IPA. This new UI is a native approximation of the reference, not a claim of pixel-exact reconstruction.

The framework stores its installation identifier/session in Keychain, calls the real activation and account API, displays expiry, and rechecks active sessions. It fails closed on network errors. Apps must call `ActivationAccessActive()` at protected feature entry points; merely showing an overlay does not enforce licensing.

`ActivationAccountFrame()` can be called by a host account-tab render callback. The host binary adapter, game feature gates, signing, callback compatibility, rotation/keyboard handling, and on-device testing are still required. Loading the framework alone is insufficient. Do not remove the host application's checks without replacing them with real gates.

## Licensing scope

This is an installation-bound session scheme, not hardware attestation or unbreakable anti-tamper protection. The server's administrator identity must never be embedded in this client.
