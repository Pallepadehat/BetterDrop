# Contributing to BetterDrop

Thanks for wanting to make it better! Bug reports, ideas, new effects and smoother gestures are all welcome.

## Getting set up

1. Xcode 26 or later, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) if you'll add files.
2. `open BetterDrop.xcodeproj`. Pick the **BetterDrop macOS** or **BetterDrop iOS** scheme, choose your own team under **Signing & Capabilities** (a free Apple ID works for running on your own iPhone), and run.
3. Test with `swift test --package-path Packages/BetterDropKit`, or ⌘U on the macOS scheme.

Try it on a real iPhone and Mac when you can. The Simulator has no Bluetooth, so it can't feel how close the Mac is.

The project file is generated from `project.yml`. If you add, move or delete files, run `xcodegen generate` and commit the regenerated project with your change.

## Where things are

```
Packages/BetterDropKit/          everything both apps share
  Sources/BetterDropCore/        models, the library on disk, the wire format, the crypto
  Sources/BetterDropTransport/   Bonjour, Bluetooth proximity, the live link, background transfers
  Sources/BetterDropUI/          the look: Metal shaders, the orb, cards, the grid
    Shaders/Light.metal          every effect, one GPU pass each
Apps/iOS/                        the iPhone app
Apps/macOS/                      the Mac app (menu bar, the light at the screen edge)
Apps/Shared/                     the asset catalog both apps use
scripts/                         build, release and brand scripts
docs/                            the protocol, and the README's pictures
```

## Easy first contributions

- **Tune the light.** Every effect is a function in `Light.metal`. After changing one, run `./scripts/make-brand.sh`: it redraws the icons and every picture in the README with the shaders, so you can see your change without a device.
- **More file types.** How a card is drawn is decided by `DropItem.Kind` in `BetterDropCore/Models/DropItem.swift`.
- **Accessibility.** Every effect should respect Reduce Motion, and everything you can do with a gesture should be possible with VoiceOver.

## Ground rules

- **Direct and private.** Files never go through a server. No analytics, no telemetry, no accounts.
- **Encrypted, always.** Anything new on the wire goes through `SecureChannel` or `FileCipher`. If you touch the protocol, update [docs/PROTOCOL.md](docs/PROTOCOL.md) and add tests.
- **Fast.** Effects are single shader passes that pause when nothing moves. No stacks of blurs, no timers when idle.
- **Match the style.** Plain Swift and SwiftUI, small files, comments that explain *why*. Plain, friendly English in the interface.

## Pull requests

- Keep each one to one thing, and say what it changes and how you tried it.
- Include a recording for anything you can see.
- Make sure it builds and the tests pass.

By contributing you agree that your work is shared under the project's [MIT License](LICENSE). Please follow the [code of conduct](CODE_OF_CONDUCT.md).
