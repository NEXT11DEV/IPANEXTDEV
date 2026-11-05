# SkinProbe

Read-only Objective-C runtime metadata collector for the attached donor IPA. This is a diagnostic step toward a Skins port; it does not add or unlock Skins, bypass a login, or change gameplay.

On the iPhone, open the original Skins menu, choose a cue and league badge if the original app permits it, and tap the purple `فحص Skins` button. Use the share sheet to save `SkinProbe-report.json`, then attach that report to this conversation. If Skins cannot be opened, export the report anyway; zero donor method entries are a useful diagnostic result.

The report contains class names, selector names, method signatures, library basenames, and implementation offsets relative to each image. It does not read account field values, activation codes, tokens or device identifiers, and makes no network requests. It does not call game methods or modify their implementations. The button is added to the existing foreground window; the report is generated only on tap.

Compile with `bash build.sh` on macOS with Xcode. The resulting framework and app need signing. `package_probe.py` adds the framework to a separate copy of the donor IPA, retains all original libraries/assets, and verifies that no original code sections changed. It never overwrites the working ActivationKit IPA. A successful build and archive check do not establish that the app runs on-device.
