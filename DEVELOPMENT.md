# Development guide

Everything for building, hacking on and releasing PodDock: local builds, IDE setup, and the tag-triggered release pipeline with its secrets.

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

How the tag-triggered release pipeline (`.github/workflows/release.yml`) is configured: every secret it needs, where the value comes from, and how to add it to GitHub.

### Pipeline at a glance

| Job | Output |
| --- | --- |
| `app` | `PodDock-macOS-arm64.zip` — Developer ID signed, notarized, stapled |
| `mcp-image` | `ghcr.io/<owner>/PodDock/poddock-mcp` — multi-arch (amd64 + arm64) Docker image |

The Docker job needs **no secrets** — it authenticates to GHCR with the built-in `GITHUB_TOKEN` (`packages: write` permission is already declared in the workflow).

### Prerequisites

An active **Apple Developer Program** membership. Developer ID certificates and notarization are not available on free accounts.

### The six secrets

Add each under **Settings → Secrets and variables → Actions → New repository secret**.

#### 1. `APPLE_CERTIFICATE_BASE64`

Your **Developer ID Application** certificate as a base64-encoded `.p12`.

Creating the certificate (once):

1. Sign in at [developer.apple.com](https://developer.apple.com/account) → **Certificates** → **+**.
2. Choose **Developer ID Application**. (If the option is greyed out, your account role lacks access or the membership is not active.)
3. Follow the CSR flow — generate the CSR from a Mac whose Keychain will hold the private key, upload it, download the `.cer`, and double-click to import.
4. Verify in **Keychain Access → My Certificates** that "Developer ID Application: *Your Name (TEAMID)*" appears **with a private key underneath**. No key = the CSR came from another Mac.

Export and encode:

```bash
# Keychain Access → My Certificates → select BOTH the certificate and its key
# File → Export Items → save as .p12, set a password
base64 -i developer-id.p12 | pbcopy   # macOS clipboard; on Linux: base64 -w0 developer-id.p12
```

Paste the clipboard into the secret. It is a single long line — make sure no newlines were added.

#### 2. `APPLE_CERTIFICATE_PASSWORD`

The password you set while exporting the `.p12` above. Nothing else — but it must match exactly or `security import` fails in CI.

#### 3. `KEYCHAIN_PASSWORD`

An arbitrary random string. CI creates a throwaway keychain, and this is its password — it never unlocks anything real. Generate one:

```bash
openssl rand -hex 20
```

#### 4. `APPLE_ID`

The email address of the Apple Developer account used for notarization. Must belong to the same team as the certificate.

#### 5. `APPLE_APP_SPECIFIC_PASSWORD`

Notarization cannot use your account password (2FA). Generate an app-specific password:

1. Go to [appleid.apple.com](https://appleid.apple.com) → sign in.
2. **Sign-In and Security → App-Specific Passwords** → **+**.
3. Label it (e.g. `poddock-notarytool-ci`) and copy the generated `xxxx-xxxx-xxxx-xxxx`.

#### 6. `APPLE_TEAM_ID`

The 10-character team identifier. Find it either at developer.apple.com → **Membership Details → Team ID**, or locally:

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
# → "Developer ID Application: Your Name (ABC123DEFG)" — the part in parentheses
```

### Cutting a release

1. Bump `MARKETING_VERSION` in `PodDock.xcodeproj/project.pbxproj` (both Debug and Release rows) to match the tag.
2. Commit, then:

   ```bash
   git tag v0.1.0
   git push origin main --tags
   ```

3. The pipeline builds a **draft** GitHub Release — review, then publish.

Tag naming drives the Docker tags: `v1.2.0` → `1.2.0`, `1.2`, `latest`; a hyphenated tag (`v1.3.0-rc1`) is treated as a prerelease and skips `latest`.

### Troubleshooting

| Symptom | Cause |
| --- | --- |
| `security import: MAC OS X error -26275` / wrong password | `APPLE_CERTIFICATE_PASSWORD` mismatch with the `.p12` |
| Archive fails with "no signing certificate" | Certificate is not Developer ID **Application** (Installer/Mac App Distribution won't work), or the secret contains line breaks |
| Notarization 403 / "untrusted client" | `APPLE_ID` not on the certificate's team, or app-specific password revoked |
| `stapler` fails after successful notarize | Rare timing issue; re-run the job |
| GHCR push 403 | Workflow was forked — `GITHUB_TOKEN` package write only works in the original repo |
