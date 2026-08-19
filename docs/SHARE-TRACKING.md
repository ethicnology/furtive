# Shared live tracking — design and threat model

Sharing a live recording with someone who has no app: they open a link in a
browser and watch the track move. Nostr relays carry the data, the app encrypts
it end-to-end, and the key never leaves the URL fragment.

This document is the contract. It exists so the implementation cannot quietly
promise more than it delivers — if the code and this file disagree, the file is
right and the code is a bug.

## What is guaranteed

- **The relay never sees a position.** Payloads are NIP-44 v2 (ChaCha20 +
  HMAC-SHA256, audited by Cure53 in December 2023, with published test vectors).
  A relay operator sees ciphertext, a throwaway public key, and timing.
- **No long-term nostr identity is involved.** One ephemeral keypair per share,
  generated on the device, never persisted, never reused. The event keys do not
  cryptographically link two shares to each other or to a nostr identity, and
  the app stores no long-term key material of any kind. This is not a network-
  anonymity guarantee: relay metadata can still correlate shares as described
  below.
- **The observer cannot be fed a forged track.** Not because of the `authors`
  filter — that is a *request*, and a relay is free to answer with something else
  — but because forging a position requires the NIP-44 conversation key, which
  needs the link secret. Anyone else's payload fails the HMAC. The pinned key and
  the local signature check are what keep the viewer from even processing it; see
  "What the client must do".
- **The link key is never transmitted.** It lives in the URL fragment, which
  browsers do not send in HTTP requests and do not put in the `Referer` header.

## What is NOT guaranteed — read this before writing UI copy

- **The viewer's host is trusted at each visit.** The fragment stays in the
  browser, but the JavaScript that reads it is served by someone. A compromised
  or malicious host can serve a build that exfiltrates the key, targeted at one
  visitor. This is inherent to browser-delivered cryptography and cannot be
  fixed inside this design — only narrowed (static build, no third-party
  origins, strict CSP).
- **Expiry does not revoke anything.** The observer holds the key; everything
  already received is theirs forever. Expiry means exactly one thing: *the phone
  stops publishing*. NIP-40 `expiration` is sent as hygiene, and relays "MAY
  persist [expired events] indefinitely" per the NIP itself. Never present it as
  a security control.
- **Revocation is: stop sharing, then issue a new link.** There is no way to
  claw back a key that has been handed out.
- **The relay learns metadata and may correlate shares.** It sees the publishing
  device's IP, connection timing, cadence, relay selection, and the fact that
  *someone* is sharing a live track right now. Reusing the same network session
  or address can let a relay associate otherwise independent ephemeral keys.
  Only the content is hidden — and, since every update is padded to a constant
  length, the *size* carries nothing either (see below).
- **A leaked link is a leaked track.** Anyone holding it — a forwarded message,
  a screenshot, a browser-history sync — sees the same thing the intended
  recipient sees, unless a password was set.
- **No forward secrecy.** NIP-44 states this plainly. A key obtained later
  decrypts everything captured earlier.

## Link format

```
https://<viewer-host>/#<version>.<publisher-pubkey>.<share-secret>.<relays>
```

Every segment after the version is base64url **without padding** (`=` would have
to be escaped in a URL).

| Segment | Bytes | Purpose |
|---|---|---|
| `version` | — | `v1` plain, `v1p` when a password is required. |
| `publisher-pubkey` | 32 | Pins the author, so the viewer can refuse an event it did not ask for instead of trusting the relay's filtering. |
| `share-secret` | 32 | Random. Everything the observer needs is derived from it. |
| `relays` | var | Comma-joined relay hosts, `wss://` implied and enforced. |

The descriptor is capped at 8192 characters, with at most eight relays and 512
UTF-8 bytes per relay URL. These are security bounds: opening a link must not let
an attacker allocate an arbitrary buffer or make the browser maintain an
arbitrary number of websocket/reconnect loops.

The password requirement is **announced** in the version rather than discovered.
A viewer that had to guess could not tell "needs a password" from "the share has
ended": a wrong master derives a different topic, so it matches no events at all.
The cost is that whoever holds the link learns a password exists — which they
would learn on their first attempt anyway.

`ws://` is unrepresentable, not merely discouraged: a browser refuses a plaintext
websocket from an https page, so a `ws://` relay would work on the phone and fail
for every observer.

The relay list travels **in the link** rather than being a viewer default. A
share published to a self-hosted relay must be readable by someone whose viewer
has never heard of it, and defaults that drift over time must not silently break
old links. Measured with two relays: a 123-character fragment, 150 characters of
URI including the host — comfortably QR-friendly.

### Key derivation

`S` is the 32-byte `share-secret` from the fragment.

```
no password:   master = S
with password: master = Argon2id(password, salt = S,
                                 m = 19456 KiB (19 MiB), t = 2, p = 1,
                                 out = 32 bytes)

recipient secret key = HKDF-SHA256(master, info = "furtive-share-recipient-v1")
topic (`d` tag)      = HKDF-SHA256(master, info = "furtive-share-topic-v1")[0:16]
```

Those parameters are the OWASP Password Storage Cheat Sheet's headline Argon2id
configuration. OWASP lists five it considers equally strong, trading CPU against
RAM (46 MiB/t=1 down to 7 MiB/t=5); this one is picked because Argon2's work is
roughly proportional to m×t, making 19×2 the cheapest of the five — and cheap
matters, because the viewer runs it in a browser on pointycastle's register64
path. Measured at 158 ms on the native-int path here.

They are **contract, not tuning**: both sides must derive the same bytes, so
changing one bumps the link version and invalidates every link already sent.
Going below the OWASP minimum is not available to us — a leaked link would become
brute-forceable offline, which is the only attack the password exists to stop.

Derivation **blocks the isolate that calls it**, and the API is synchronous on
purpose so that the caller chooses how to absorb that: the app offloads to
`Isolate.run`, while the viewer has no isolates and must paint its progress
indicator and yield to the event loop before calling. Hiding it behind a Future
would let both believe the work was already elsewhere.

Measured cost of a password-protected derivation, same input, same vectors:

| Target | Argon2id |
|---|---|
| Dart VM (native-int implementation) | 158 ms |
| dart2js under Node 20 (register64 implementation) | **3343 ms** |

A 21× gap, because the browser has no 64-bit integers and pointycastle emulates
them. On a mid-range phone browser it will be worse. The progress indicator is
therefore not a nicety, and it must be on screen *before* the call.

The same run verified something more important: **the two implementations produce
identical bytes**. The frozen vectors were reproduced exactly under dart2js, which
also exercises HKDF, the secp256k1 public-key derivation and JSON number handling
on the web path. Had they disagreed, every password-protected share would have
been unreadable in the browser while looking correct on the phone.

The password is the Argon2id *password* and the link secret is the *salt*, in
that order. Concatenating them into a hash instead would turn a leaked link into
a GPU-speed dictionary attack.

HKDF takes no salt: the input is already 32 uniformly random bytes. The two info
labels are what domain-separate the decryption key from the publicly visible
topic — a relay operator knowing the topic learns nothing about the key.

Both derivations are frozen by test vectors in `test/share_keys_test.dart`. They
are a tripwire, not authority: the phone and the browser may run different app
versions and must still agree, and a link already sitting in someone's messages
cannot be migrated.

The recipient key is a secp256k1 secret and must land in `[1, n-1]`; on the
astronomically unlikely miss, the HKDF info gets a counter suffix and is retried.

NIP-44 conversation keys are symmetric: the publisher encrypts with its own
secret and the recipient's public key, and the observer decrypts with the
recipient's secret — derived above — and the publisher's public key, read from
the pinned value. Neither side needs to transmit anything extra.

A password is only meaningful if it is **not** in the link: it is typed by the
observer. Without it the fragment alone is useless — the topic cannot even be
computed, so the viewer cannot subscribe, let alone decrypt.

## On the wire

| | Kind | Stored by relays | Cadence |
|---|---|---|---|
| Live positions | `22222` (ephemeral) | no, by design (NIP-01) | one event per 10 s |
| Recent history | `32222` (addressable) | latest snapshot only, per `(kind, pubkey, d)` | refreshed every 30 s |

Ephemeral events are not retained, so an observer opening the link mid-run would
otherwise see a blank map until the next fix. The addressable event is what they
bootstrap from. It contains at most 60 sampled updates — ten minutes at the live
cadence — and is padded to a fixed 12,288-character plaintext envelope so its
size does not disclose how long the share has been running. It is the one piece
of the design that deliberately leaves recent route data at rest on a relay,
which is why it carries the same NIP-40 expiration.

Both kinds were checked against the **machine-readable registry**
(`nostr-protocol/registry-of-kinds`, `schema.yaml`), which is the only list that
counts: the table in the NIPs README states it is not exhaustive, and checking
only that table is how an earlier draft of this design ended up on kind `21000` —
registered as *Lightning Pub RPC*. A collision puts our ciphertext in front of
clients that believe they know what the kind means.

The registry has open pull requests, so re-check before release:

```sh
curl -sSf https://raw.githubusercontent.com/nostr-protocol/registry-of-kinds/master/schema.yaml \
  | grep -E '^\s*(22222|32222):'
```

Plaintext, before NIP-44, is compact JSON. Keys are terse to keep the payload
small on a mobile connection — no longer to control the padding bucket, which is
now fixed for every update regardless (see "Constant-length payloads"):

```json
{"v":1,"p":{"t":1785421513000,"y":45.5019,"x":-73.5674,"s":"a",
            "e":132.5,"a":4.5},"b":1785420184000,"d":4231.75,"el":1329}
```

`t` is the fix's unix milliseconds UTC, `y`/`x` are latitude/longitude, `s` is
the point status (`a` active, `p` paused, `s` signal lost), `e` elevation and `a`
accuracy are optional, `b` is the recording's wall-clock start in unix
milliseconds UTC, `d` is active distance in metres and `el` active elapsed
seconds. `b` is transmitted because subtracting active elapsed time from `t`
produces the wrong start after a pause.

`f` is present, as `1`, on exactly one update: the last of the share. It is
omitted otherwise, so it costs nothing on the wire, and the constant padding
hides the difference in length. It exists because without it the end of a share
is indistinguishable from a phone that ran out of battery — the publisher simply
stops, and the observer watches a counter climb forever.

`f` was added to v1 rather than bumping the link version, which the rule above
permits: it is additive in both directions. A viewer predating it ignores the
key, exactly as it already ignores the padding filler, and a publisher predating
it omits it, which a newer viewer reads as "still running". What that rule
forbids is changing an existing spelling, not adding an optional field.

Totals travel rather than being recomputed: a viewer only ever sees a sampled
subset of the track — ephemeral events it missed are gone — so summing what it
received would under-report distance and disagree with the recorder's own screen.

There is no sequence number. Relays may deliver out of order, and the observer
sorts by `t` regardless, since it has to merge the addressable bootstrap event
with the live stream.

Required fields are refused when malformed; optional ones degrade to absent. A
garbled elevation must not cost the observer the position it arrived with, but a
position without coordinates is not a position.

Every numeric field is bounded, because each unbounded one has a specific failure:

| Field | Range | What an unbounded value does |
|---|---|---|
| `y` / `x` | ±90 / ±180, finite | A non-finite coordinate poisons MapLibre's camera and every later gesture throws. JSON smuggles one as `1e999`, which decodes to `Infinity`. |
| `t` | 0 → 2100-01-01Z | The observer sorts by time, so a point claiming the year 5138 pins itself to the end of the trace for the whole session. |
| `b` | 0 → 2100-01-01Z | The wall-clock recording start cannot be reconstructed from active elapsed time across pauses. It may be slightly after the first GPS timestamp when that fix was captured just before recording began. |
| `el` | 0 → 30 days | A negative elapsed makes the viewer compute a negative pace, which renders as a plausible-looking number. |
| `d` | 0 → 40 075 km | One Earth circumference; a negative or absurd distance is not a recording. |
| `e` | −500 → 20 000 m | Optional, so an out-of-range value is dropped rather than fatal. `1e300` is perfectly finite and would wreck any chart axis it reached. |
| `a` | 0 → 100 000 m | A negative accuracy is not a radius. |

### Constant-length payloads

Every live update is padded to **192 characters** before encryption, and every
recent-history snapshot to **12,288 characters**, with the filler in a key
`decode` ignores.

NIP-44's own 32-byte bucketing is not enough. Measured without this padding: a
fresh share encrypted to 220 characters and one a few kilometres in to 260,
because the distance and elapsed numbers grow digits and the optional fields come
and go. A relay operator sees every ciphertext, so that alone was enough to tell a
share that had just started from one well underway, and to watch it progress —
without decrypting anything. With padding, every update encrypts to 348
characters, whatever it says.

Integers accept both `60` and `60.0`. dart2js has a single number type, so the
browser sees an integral double where the phone sent an int — parsing must not
depend on which side decoded the JSON.

## What the client must do

These are obligations, not suggestions. Each one closes something the format alone
cannot.

- **Validate the event signature before decrypting.** NIP-44 states that the outer
  NIP-01 signature authenticates the whole payload and MUST be checked first; the
  HMAC is computed before signing precisely because the signature is assumed to be
  there. Pinning `authors` in the filter is not a substitute — a relay is not
  trusted, and it chooses what to return.
- **Refuse a position outside a freshness window, but do not demand strict
  monotonicity.** Nothing stops a relay from replaying an earlier, still-unexpired
  event, which would put the observer back at a place the sharer has left. The
  defence is already in the format: `t` sits *inside* the ciphertext, so it is
  authenticated and a relay cannot alter it. But relays also deliver out of order
  in normal operation, so dropping everything older than the newest `t` seen would
  discard legitimate points — the rule is a window (a few multiples of the publish
  cadence), not a ratchet. The shipped viewer accepts at most 15 minutes of age
  and two minutes of future clock skew. Move the cursor only forward; accept
  slightly late arrivals and sort them into place.
- **Expect relays to refuse events over clock skew.** NIP-01 lists
  `invalid: event creation date is too far off from the current time` among the
  standard rejections, and a phone clock is often wrong. That failure must reach
  the user as a cause, not as a share that silently publishes nothing.
- **Never divide by the elapsed time without guarding it.** `d` may be positive
  while `el` is zero — legitimately, because `el` is whole seconds and the first
  fixes of a recording can land inside one, and hostilely, because a relay can
  send whatever it likes. Verified: it yields a speed of `Infinity`. This is the
  same argument as bounding coordinates to protect the camera, one derivation
  further out, and the format cannot tell the two cases apart.
- **De-duplicate exact points.** The bootstrap addressable event and the live
  stream overlap by design, so the same position arrives twice. Timestamp alone
  is insufficient: signal-loss boundary points can deliberately share one
  millisecond while carrying different status/coordinates.
- **Draw the track without WebGL.** Measured: combining Flutter CanvasKit and
  MapLibre gives Firefox two WebGL renderers and can block its main thread for
  tens of seconds. The selected viewer uses Leaflet's DOM/SVG path instead.
- **Read the fragment directly from `location.hash`.** The selected viewer is a
  Dart Web application, not Flutter Web, so no framework router owns or rewrites
  the fragment.
- **Paint the progress indicator before deriving with a password**, and expect to
  hold it for five to twelve seconds in a browser — not the 3.3 s a Node
  measurement suggests.

## What the spike measured

A throwaway publisher and three web renderers (MapLibre under Flutter,
`flutter_map`, and Leaflet under Dart Web) were built against this format and run
for real. The publisher signed and encrypted a wandering track and pushed it to
public relays; each viewer read the fragment, subscribed, validated and
decrypted. Findings, in descending order of consequence.

**The pipeline works end to end.** 25 positions out of 25 accepted, none refused,
live from `wss://nos.lol` and `wss://relay.primal.net`, with `active` and
`signalLost` preserved and both event kinds flowing. 1651 events published, every
one acknowledged `true` by both relays — anonymous writes are viable.

**The final web renderer is Dart Web plus Leaflet.** The full encrypted viewer
starts without Flutter, CanvasKit, or MapLibre. Its compressed application bundle
measured 169 KiB. Under the same Firefox session, link parsing, key derivation,
relay connection, first decryption, map creation, and route rendering completed
in roughly one second once static assets were compressed.

**MapLibre is rejected for this viewer, not for the mobile app.** In Firefox the
Flutter/MapLibre prototype loaded Flutter and decrypted its first position in
about one second, then blocked for 20–65 seconds while the second WebGL renderer
loaded and painted raster tiles. A same-origin tile proxy proved the network was
not the bottleneck: a cold tile measured 66–256 ms and a cached tile under 12 ms.
`flutter_map` removed the second WebGL context and performed well, but retained
the Flutter engine and a 741 KiB compressed application bundle. Leaflet gave the
best startup and keeps controls in ordinary DOM, so it is the selected web path.

The phone remains free to use its existing MapLibre implementation. This decision
is scoped to the read-only browser viewer, where a second rendering engine buys
nothing and WebGL is not an acceptable prerequisite.

**The one-point bootstrap was rejected.** Measured against a
publisher that had been running for an hour and had pushed over 1800 positions:
a viewer opening the link received **2**. That is the ephemeral design working as
specified — relays do not retain kind 22222 — but the effect is a product defect
for a feature whose point is watching someone move. The addressable bootstrap now
carries the most recent 60 sampled updates, and the threat model says plainly
that this leaves up to ten minutes of encrypted route data at rest on a relay.

**Flutter Web owned the `#` in the discarded prototype.** Its bootstrap could
normalise the URL before `main()` read it. Dart Web plus Leaflet has no router, so
the final viewer reads `location.hash` directly and still never sends it in an
HTTP request or referrer.

**Argon2id in a browser costs seconds, and WebAssembly does not rescue it.**

| Target | Argon2id (same input, same vectors) |
|---|---|
| Dart VM, native-int implementation | 158 ms |
| dart2js under Node 20 | 3343 ms |
| dart2wasm, Firefox 153 | 5550-11483 ms, ~2× run-to-run variance |

Byte-identical everywhere, so correctness is not in question — but a
password-protected share costs the observer between five and twelve seconds, and
unpredictably. WASM is only ~3 % faster than dart2js, because pointycastle gates
its 64-bit implementation on `const _fwInteger = 9007199254740992 + 1 != 9007199254740992`,
a *constant* the Dart front end evaluates with JavaScript number semantics for
every web target — dart2wasm included, despite wasm having real 64-bit integers.
Importing the native-int implementation directly is refused at runtime with
`full width integer not supported on this platform`. So the cost is an artefact of
upstream packaging rather than a property of WASM, and it is fixable — by
vendoring Argon2id against our frozen vectors, or upstream. Until then, treat
five to twelve seconds as the real figure. The password-less path is HKDF only:
117-167 ms.

**The share layer is a real package boundary.** `packages/furtive_share` owns the
four wire/crypto modules and their pure-Dart tests. Both the Flutter app and
the Dart Web viewer resolve that same path package; its only runtime dependencies
are `nostr` and `pointycastle`. CI analyzes and tests it independently, then
compiles the viewer against it.

## Relays

Writes are anonymous, which is precisely what relay anti-spam exists to refuse.
Measured against five public relays: two accepted every write and served the
addressable event back, one refused with `restricted: sign up …`, and two failed
at the connection level. **Relay failure is the normal case**, so:

- publish to every enabled relay, treat per-relay failure as expected, and keep
  health per relay rather than a single global "connected" flag;
- surface `OK false` prefixes to the user in plain language — `restricted` and
  `auth-required` mean "this relay will never accept an anonymous share, pick
  another one", which is a different message from `rate-limited`;
- if a relay answers `pow:`, NIP-13 proof-of-work is the anonymous-friendly
  currency. Pay it for the addressable event only; a per-position PoW on battery
  is not worth it.

Two defaults ship in the build configuration. Distributors can replace them with
the `SHARE_RELAYS` compile-time setting, including a self-hosted relay. There is
no identity to authenticate with, so NIP-42 is not available to this feature.

## Boundaries in the app

- **The publisher listens to `RecordingBloc`, never to the GPS stream.** It wants
  recorded points — already past the quality gate, already carrying pause and
  signal-loss status — so pause semantics come for free and the recording path is
  not modified at all. A dead relay cannot cost a single point of trace, by
  construction rather than by care.
- **The publisher is opt-in and memory-only.** `LiveShareCubit` creates one
  ephemeral session when the user taps the live-share control. Regular points
  are sampled to 10 s, status transitions publish immediately, and snapshots
  refresh every 30 s. A process kill ends the share: restoring its keys would
  require persisting them, contradicting the memory-only promise. The link
  remains readable only for already-published data.
- **A share may be armed before the recording exists.** The link can be created
  first, publishes nothing while it waits, and binds to the first recording that
  starts. Binding happens once and is never redone, because the viewer's totals
  are deliberately monotonic: distance and elapsed only grow and the start time
  only moves earlier, so a second recording would leave the observer looking at
  the first one's figures forever. Following several recordings would require an
  activity identifier on the wire and a reset path in the viewer.
- **One share follows exactly one recording, and says when it ends.** When the
  bound recording stops — or the user stops sharing — the publisher sends a last
  update carrying `f`, refreshes the snapshot so a late opener reads it too, and
  only then closes the sockets. Tearing down first would cut that update in
  flight. A leaked link therefore cannot stream a *later* recording, which is the
  privacy property arming had to preserve.

  One consequence worth stating: if the recording ends while a password is still
  being derived, which takes seconds, the share does not fail. It stays armed and
  will follow the next recording instead.
- **A production build must set `SHARE_VIEWER_URL`.** Without a canonical HTTPS
  viewer origin the live-share control is hidden rather than generating a broken
  or insecure link. HTTP is accepted only for loopback development URLs.
- **The share code holds no Flutter, drift or geolocator import.** It lives in
  `packages/furtive_share`, consumed by both the app and the Dart Web viewer; a
  CI check additionally enforces the sensor/storage denylist.
- **The viewer enables tiles by default as an explicit product decision.** Tile
  requests disclose the viewed area to whichever service terminates them. The
  basemap is a compile-time setting (`TILE_URL`) defaulting to the same-origin
  `/tiles/{z}/{x}/{y}.png`, so a self-hosted viewer contacts no third-party tile
  host. Production must provide that first-party endpoint or state the
  disclosure plainly. The observer can disable the basemap without affecting the
  encrypted route.
- **The GitHub Pages deployment takes the second option, and this is the plain
  statement.** A static host cannot proxy tiles, so that build loads CARTO's
  public basemap: every visitor discloses the area they are watching to CARTO,
  which the same-origin default exists to avoid. The route itself stays
  end-to-end encrypted — CARTO sees tile coordinates, never a position. The
  packager grants exactly that one origin in `img-src`, never a wildcard.
- **That deployment is for verification, not production, and the gap is wider
  than the CSP alone.** Measured on `https://furtive.ethicnology.com/share/`
  (2026-08-19), Pages returns `server`, `content-type`, `etag`, `cache-control`,
  `access-control-allow-origin: *` and its cache telemetry — and none of
  `content-security-policy`, `x-frame-options`, `strict-transport-security`,
  `referrer-policy`, `permissions-policy` or `x-content-type-options`. Two
  consequences are worth naming rather than implying:
  - **No clickjacking guard at all.** `frame-ancestors` is ignored in a `meta`
    element, and the legacy `x-frame-options` fallback is not sent either, so
    nothing stops the page from being framed — on the page where the observer
    types the share password.
  - **No HSTS, even with Enforce HTTPS on.** Enforcing HTTPS buys the 301 from
    `http://`, which is measured and works, but no `Strict-Transport-Security`
    header is sent for a custom domain, and a custom domain does not inherit the
    preload entry `github.io` has. First-contact downgrade therefore rests on
    the browser's own HTTPS-first behaviour, not on anything this deployment
    asserts.

  The `meta` CSP still applies, so script, style, image and `wss:` origins stay
  constrained; it is the header-only directives that are missing. Moving to a
  host that sends headers closes both gaps, and the deployment lives on a
  dedicated domain precisely so it can move without breaking emitted links.
- **The viewer origin is a compiled-in constant, so the domain is the seam.**
  Links are minted against `SHARE_VIEWER_URL`, published at
  `https://furtive.ethicnology.com/share/`, and every APK carries that string
  forever. Hosting is therefore free to change; the URL is not. The root of that
  domain serves a script-free presentation page: a share key sits in the fragment
  of a `/share/` URL, so no code outside the audited viewer bundle — analytics,
  fonts, a router at the root — may ever be in a position to read one.

## Rejected alternatives

- **Signing with the user's own nostr identity.** The pubkey is public metadata:
  anyone knowing the npub could enumerate when, how often and for how long that
  person shares a live track, correlated with all their other nostr activity. It
  would have bought access to restricted relays. A self-hosted relay buys that
  without the disclosure.
- **Storing a long-term nsec in the app.** Nothing to protect is strictly better
  than something to protect: no keystore dependency, and no way for a key to
  reach the log export.
- **Hand-rolled AEAD.** NIP-44 v2 is audited and has published test vectors.
- **A password inside the link.** Decorative — it protects against nothing that
  the link itself does not already expose.
- **Veilid.** Its browser path is a WASM node with bootstrap, against a
  ~50 KB-of-JSON websocket alternative. Revisit if relay hostility to anonymous
  writes ever becomes the binding constraint.
