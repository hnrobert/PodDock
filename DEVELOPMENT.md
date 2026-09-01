# Development guide

Everything for building, hacking on and releasing PodDock: local builds, IDE setup, and the tag-triggered release pipeline.

## Building

```bash
# DNSPodKit unit tests (fast lane)
cd DNSPodKit && swift test

# App (macOS)
open PodDock.xcodeproj   # scheme: PodDock

# Standalone MCP server (zero startup credentials; auth via in-session dnspod_login)
cd DNSPodKit && swift run poddock-mcp
# Hook it up: claude mcp add --transport http poddock http://127.0.0.1:28100/mcp
# then ask the model to call dnspod_login with your "ID,Token"
```

## IDE indexing

VS Code needs a one-time machine-local SourceKit-LSP config (gitignored):

```bash
brew install xcode-build-server   # first time
scripts/setup-lsp.sh              # generates buildServer.json pointing at the repo-local .build/DerivedData
```

Reload the window afterwards for full completion/jump-to/diagnostics across both app sources and the SPM package. Re-run it whenever the scheme or project layout changes.

## Releasing

The pipeline (`.github/workflows/release.yml`) triggers on `v*` tags.

| Job | Output |
| --- | --- |
| `app` | `PodDock-macOS-arm64.zip` — signed with your Apple Development certificate, arm64 only |
| `mcp-image` | `ghcr.io/<owner>/PodDock/poddock-mcp` — multi-arch (amd64 + arm64) Docker image, authenticated with the built-in `GITHUB_TOKEN` |

### Secrets (3)

Add them under **Settings → Secrets and variables → Actions**:

| Secret | Value |
| --- | --- |
| `APPLE_CERTIFICATE_BASE64` | Your Apple Development certificate `.p12`, base64-encoded: `base64 -i cert.p12 \| pbcopy` |
| `APPLE_CERTIFICATE_PASSWORD` | The password set when exporting that `.p12` |
| `KEYCHAIN_PASSWORD` | Any random string (`openssl rand -hex 20`) — password of the throwaway CI keychain |

The team ID is parsed automatically from the imported certificate; no separate secret for it. No Apple ID or app-specific password is needed — signing alone does not involve them.

### Obtaining the certificate (Keychain Access)

An **Apple Development** certificate is created automatically the first time you build and run a project in Xcode with your Apple ID signed in (Xcode → Settings → Accounts). A free Apple ID is enough — no paid Apple Developer Program membership. If you have ever run an app from Xcode on this Mac, the certificate is most likely already in your keychain.

Verify and export it:

1. Open **Keychain Access** → **login** keychain → **My Certificates** category.
2. Find `Apple Development: <your-email> (TEAMID)` — e.g. `Apple Development: user@example.com (9TYSNKGT39)`.
   - It **must sit under "My Certificates" with a disclosure triangle revealing a private key underneath**. If it only appears under "Certificates" without a key, the private key lives on another Mac (or is lost) — see below.
   - Check the expiry date in the cert details; anything in the future is fine.
3. Select **both** the certificate **and** its private key (⌘-click), then **File → Export Items**.
   - Format: **Personal Information Exchange (.p12)**
   - Set a password — this becomes `APPLE_CERTIFICATE_PASSWORD`.
4. Encode it:

```bash
base64 -i ~/Desktop/certificate.p12 | pbcopy   # macOS clipboard; paste into APPLE_CERTIFICATE_BASE64
```

The result is one long single line — make sure no line breaks got pasted in.

**No usable certificate in Keychain?** Have Xcode create one: Xcode → Settings → Accounts → select your Apple ID → **Manage Certificates…** → **+** → **Apple Development**. This revokes and re-issues on the current Mac, so export the fresh cert afterwards and update the secret.

**Renewal:** these certificates are valid for roughly a year. Xcode renews them transparently when they expire — when that happens, re-export the new `.p12` and update `APPLE_CERTIFICATE_BASE64` / `APPLE_CERTIFICATE_PASSWORD`.

### Cutting a release

1. Bump `MARKETING_VERSION` in `PodDock.xcodeproj/project.pbxproj` (both Debug and Release rows) to match the tag.
2. Commit, then:

   ```bash
   git tag v0.1.0
   git push origin main --tags
   ```

3. The pipeline builds a **draft** GitHub Release — review, then publish.

Tag naming drives the Docker tags: `v1.2.0` → `1.2.0`, `1.2`, `latest`; a hyphenated tag (`v1.3.0-rc1`) is treated as a prerelease and skips `latest`.

### Why the app is not notarized

Notarization requires a paid Apple Developer Program membership. The app is signed with a real Apple Development certificate (stable identity, Keychain-friendly), but Gatekeeper still blocks it on other Macs at first launch. The release notes already tell recipients how to open it:

> Right-click the app → **Open** → **Open**, or run `xattr -d com.apple.quarantine /Applications/PodDock.app`.

### Upgrade path (optional, later)

Joining the Apple Developer Program unlocks Developer ID signing + notarization, which removes the Gatekeeper friction. The changes needed then:

1. Create a **Developer ID Application** certificate (developer.apple.com → Certificates; CSR from the Keychain that holds the private key) and export it as a `.p12`; swap `APPLE_CERTIFICATE_BASE64` / `APPLE_CERTIFICATE_PASSWORD` to it.
2. Add `APPLE_ID` + `APPLE_APP_SPECIFIC_PASSWORD` (appleid.apple.com → Sign-In and Security → App-Specific Passwords) and `APPLE_TEAM_ID` (Membership Details, 10 chars).
3. In the `app` job: archive with `CODE_SIGN_IDENTITY="Developer ID Application" OTHER_CODE_SIGN_FLAGS="--options runtime"`, then `xcrun notarytool submit --wait` + `xcrun stapler staple` and re-zip with `ditto`.

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| CI: `No signing certificate … with a private key was found` | The exported `.p12` contains the certificate but **not its private key** — re-export from **My Certificates**, selecting both the certificate and the key. Verify locally first: `openssl pkcs12 -info -in cert.p12 -nodes -noout -passin pass:<pw> \| grep -c "PRIVATE KEY"` (must print `1`) |
| App "cannot be opened" on another Mac | Expected without notarization — right-click → Open, or clear the quarantine attribute |
| `security import` fails / wrong password | `APPLE_CERTIFICATE_PASSWORD` does not match the `.p12`, or `APPLE_CERTIFICATE_BASE64` got line-wrapped |
| Archive: "requires a development team" | The imported certificate is not an **Apple Development** identity (export the one from Keychain Access → My Certificates) |
| GHCR push 403 | Workflow was forked — `GITHUB_TOKEN` package write only works in the original repo |
