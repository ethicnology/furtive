# Furtive live viewer

Read-only Dart Web application. It shares `packages/furtive_share` with the
mobile app and uses Leaflet directly through JS interop; Flutter, CanvasKit,
MapLibre, storage, and sensors are intentionally absent.

## Build

From the repository root:

```sh
make viewer-deps viewer-build
```

The static output is written to `build/viewer/`. It includes Leaflet 1.9.4 and
its images, downloaded from the pinned upstream release and accepted only when
their SHA-256 hashes match `tool/package_viewer.py`. The application JS and CSS
use content-hashed filenames. The directory may be reused between builds: the
packager removes superseded hashed JS and CSS so an artifact contains only the
files referenced by its current `index.html`.

## Hosting contract

The host must serve:

- dark raster XYZ tiles at `/tiles/{z}/{x}/{y}.png`, the same-origin default;
  `make viewer-build VIEWER_TILE_URL=…` retargets the basemap, and the packager
  then grants that one origin in the CSP;
- the viewer over HTTPS so links containing `wss://` relays are not downgraded;
- `index.html` without long-lived caching and content-hashed static assets with
  compression;
- a CSP that permits same-origin scripts/styles/images and `wss:` connections,
  while refusing frames, objects, sensors, and referrers.

The fragment contains key material. It must never be moved to a query parameter,
logged, sent in telemetry, or included in a referrer. Browsers do not send URL
fragments in HTTP requests.

The HTML carries a baseline CSP and `no-referrer` policy. The production server
must additionally send `frame-ancestors 'none'`, `Permissions-Policy`, HSTS and
the same CSP as headers; `frame-ancestors` is ignored in a meta element.

The Python proxy under `/tmp/opencode` is only a local spike server and is not a
production deployment component.

## GitHub Pages deployment

`.github/workflows/deploy-viewer.yml` publishes the viewer to
`https://ethicnology.github.io/furtive/`. It exists to check a real link end to
end — fragment parsing, key derivation, relay connection, decryption, drawing —
against a real browser.

It runs on every push to the working branch. That is not a preference: a
`workflow_dispatch` entry only becomes usable once the workflow file exists on
the repository default branch, and this one is kept off it for now, so pushing
is the only trigger that reaches GitHub. The manual entry is declared anyway and
starts working the day the file lands there.

It is not a production deployment, and it does not satisfy the contract above:

- Pages cannot proxy tiles, so that build points at CARTO's public basemap.
  Visitors disclose the area they watch to CARTO. The encrypted route is
  unaffected.
- Pages sends no custom headers, so `frame-ancestors`, `Permissions-Policy` and
  a header-delivered CSP are unavailable; the `meta` CSP in `index.html` is all
  there is, and `frame-ancestors` does not work from a `meta` element.

Two things must be set by hand before it works:

1. The `github-pages` environment restricts deployments by branch. Add the
   branch you dispatch from under Settings → Environments → `github-pages`, or
   the run is refused.
2. The app only produces links once built with the matching viewer origin:
   `make apk SHARE_VIEWER_URL=https://ethicnology.github.io/furtive`.
