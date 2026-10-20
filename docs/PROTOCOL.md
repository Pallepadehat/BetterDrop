# How BetterDrop talks

Everything here is implemented in `Packages/BetterDropKit`, and every claim has a test next to it.

## Finding each other

- **The Mac** advertises the Bonjour service `_betterdrop._tcp` with a TXT record: its device ID, name, kind and protocol version. It listens over Wi-Fi, Ethernet and peer-to-peer Wi-Fi (AWDL, the same link AirDrop uses).
- **It also sends out a Bluetooth beacon**: a made-up service UUID and a local name of `BD` plus the first eight characters of its device ID. Nothing connects to it. The phone only measures how strong the signal is.
- **The phone** browses for the service and listens for beacons. It smooths the signal strength, turns it into *closeness* (0 to 1), and matches beacons to Macs by the short ID. Closeness drives the light on both screens. The phone streams it to the Mac about fifteen times a second.

## Records

A connection is a stream of records: a 4-byte big-endian length, then that many bytes (4 MB at most). The first records are a plaintext handshake (JSON). Everything after it is encrypted.

## Pairing

The first time, the phone sends `pairRequest` with an ephemeral X25519 public key. The Mac answers `pairChallenge` with its own. Both compute the shared secret and a transcript hash over both keys and both device IDs:

```
salt   = SHA256("BetterDrop pairing v1" ‖ phoneKey ‖ macKey ‖ phoneID ‖ macID)
code   = HKDF-SHA256(shared, salt, "code", 8 bytes) mod 1 000 000      → six digits on both screens
secret = HKDF-SHA256(shared, salt, "pairing secret", 32 bytes)
```

Anyone in the middle would have a different shared secret with each side, so the two screens would show different codes. Accepting on the Mac is how you confirm they match. The Mac then sends `pairResult` with `HMAC(secret, "pairing accepted")`, so the phone knows the Mac it's talking to derived the same secret. Both keep the 256-bit secret: the phone in its keychain, the Mac in a file only you can read.

## Sessions

Every connection after that starts with:

```
phone → Mac   clientHello   { phone info, ephemeral X25519 key, 32-byte nonce }
Mac → phone   serverHello   { Mac info, ephemeral key, nonce, HMAC(secret, "server" ‖ T) }
phone → Mac   clientFinish  { HMAC(secret, "client" ‖ T) }

T = SHA256("BetterDrop session v1" ‖ both IDs, keys and nonces)
keys = HKDF-SHA256(X25519(ephemerals), salt: secret, info: direction ‖ T)
```

Both sides prove they hold the pairing secret, and the session keys are fresh every time. A pairing secret that leaks later can't decrypt a recording of an earlier session (forward secrecy). A Mac that has forgotten the phone answers `rejected(unknownDevice)`, and the phone pairs again.

## Messages

Every record after the handshake is sealed with **ChaCha20-Poly1305**. Each direction has its own key, and nonces are counters, so a replayed, reordered or dropped record fails to open and ends the connection. Inside:

- `0x02 | file ID | offset | bytes` is a chunk of a file, raw.
- `0x01 | JSON` is everything else: `offer`, `accept`, `decline`, `complete(sha256)`, `received`, `cancel`, `proximity`, `closeness`, `side`, `fileServer`, `backgroundOffer`, `rename`, `ping`, `pong`.

A file goes as an `offer`, an `accept`, 256 KB chunks in order, then `complete` with its SHA-256. The receiver checks every offset and the digest before the file counts as arrived. File names from the other side are sanitized: only the last path component is kept, with no leading dots, no control characters and nothing that climbs out of the folder.

## Big files, in the background

iOS only keeps moving files after you leave an app if a background `URLSession` is doing it, and that speaks HTTP. So files of 8 MB and up go to (or come from) a small HTTP server on the Mac, on the local network. The body is encrypted before it leaves:

```
salt = 32 random bytes, new for every file
key  = HKDF-SHA256(pairing secret, salt, "BetterDrop file v1")
file = chunk(0) ‖ chunk(1) ‖ … ‖ chunk(n)       1 MB each, ChaCha20-Poly1305
nonce(i) = 0x00 ‖ final? ‖ 0x0000 ‖ i (big-endian)
```

The last chunk is flagged in its nonce, so a file that's been cut short fails rather than arriving truncated.

- **Phone → Mac:** `PUT /v1/files` with headers `X-BetterDrop-Device`, `X-BetterDrop-Salt` and `X-BetterDrop-Offer` (the `FileOffer`, sealed with the file key in its own nonce space). Only a paired phone can seal an offer the Mac can open, so that's the authentication.
- **Mac → phone:** the Mac sends `backgroundOffer { offer, token, salt }` over the live connection. The phone fetches `GET /v1/files/<token>` with its device ID. Tokens are random, tied to that phone, and expire after six hours.

The Mac streams both ways: it decrypts uploads as they arrive and encrypts downloads as it reads them, so a 20 GB video never has to fit in memory or exist twice on disk.
