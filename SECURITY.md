# Security

BetterDrop moves your files between your own devices, so its promises matter: files go straight from one device to the other, never through a server, end-to-end encrypted, and only between devices you paired yourself.

How that works is written down in [docs/PROTOCOL.md](docs/PROTOCOL.md), and the code that does it is small enough to read in an evening: `Packages/BetterDropKit/Sources/BetterDropCore/Security`.

If you find a way to break any of it (read or change a file in transit, pair without the code, get a file onto someone's device without being paired, make a file land outside its folder), please **don't open a public issue**. Report it privately through [GitHub's security advisories](https://github.com/Pallepadehat/BetterDrop/security/advisories/new). You'll get a reply within a week.

## Known limits

- Releases aren't signed with an Apple Developer ID or notarized yet. The Mac app is signed ad hoc, and updates are verified with Sparkle's EdDSA signature against the key in the app.
- Pairing secrets on the Mac are kept in a file only your user can read (`~/Library/Application Support/BetterDrop/pairings.json`, mode 0600) rather than the keychain, because ad hoc signed updates would otherwise ask for your password every time. On iPhone they're in the keychain.
