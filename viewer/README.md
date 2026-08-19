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

The local Python tile proxy used while developing is a spike server, not a
production deployment component.

## GitHub Pages deployment

`.github/workflows/deploy-viewer.yml` publishes the viewer to
`https://furtive.ethicnology.com/share/`, and the presentation page at the root
of that domain. It exists to check a real link end to end — fragment parsing,
key derivation, relay connection, decryption, drawing — against a real browser.

The dedicated domain is the point of indirection the links need: the viewer
origin is compiled into the app, so hosting can later move from Pages to a host
that satisfies the contract above without invalidating a single emitted link.
A `CNAME` record points the subdomain at `ethicnology.github.io`, and
`site/CNAME` ships in the artifact so the custom domain survives a cleared
repository setting.

The site root is deliberately script-free. A share key lives in the fragment of
a `/share/` URL, so nothing outside the audited viewer bundle should ever be in
a position to read one — which also rules out routing to the viewer from a
script at the root.

It runs on pushes to the default branch that touch the viewer, the shared
package, the site root or the packager, and can be dispatched manually — a
`workflow_dispatch` entry only works from the default branch, which is also why
the paths filter is safe here: forcing a redeployment is a click, not a commit.

It is not a production deployment, and it does not satisfy the contract above:

- Pages cannot proxy tiles, so that build points at CARTO's public basemap.
  Visitors disclose the area they watch to CARTO. The encrypted route is
  unaffected.
- Pages sends no custom headers, so `frame-ancestors`, `Permissions-Policy` and
  a header-delivered CSP are unavailable; the `meta` CSP in `index.html` is all
  there is, and `frame-ancestors` does not work from a `meta` element.

Three things are set outside this repository:

1. Pages source must be `GitHub Actions`, not a branch. A branch source makes
   Pages serve the tree through Jekyll, which never compiles the viewer.
2. The `github-pages` environment restricts deployments by branch, and the
   default branch has to be among them under Settings → Environments →
   `github-pages`, or the run is refused.
3. The app only produces links once built with the matching viewer origin:
   `make apk SHARE_VIEWER_URL=https://furtive.ethicnology.com/share/`, which
   the release workflow reads from the `SHARE_VIEWER_URL` repository variable.
