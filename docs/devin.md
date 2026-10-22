---
summary: "Devin provider auth, quota endpoint, and setup."
read_when:
  - Adding or modifying the Devin provider
  - Debugging Devin localStorage import or quota parsing
  - Explaining Devin setup
---

# Devin Provider

The Devin provider tracks included daily and weekly usage quotas from
[app.devin.ai](https://app.devin.ai).

## Setup

1. Sign in to Devin in Google Chrome (any Chromium fork with localStorage works).
2. Open the organization Usage & Limits page once.
3. Enable **Devin** in **Settings → Providers**.

Automatic mode reads only the Devin session and organization metadata from Chrome localStorage. It does not scan other
browsers. CodexBar sends the session token only to `https://app.devin.ai`.

## Multiple accounts

Every Chrome/Chromium profile signed in to Devin is discovered automatically. Before each refresh, CodexBar syncs the
discovered sessions into Devin **token accounts** (Preferences → Providers → Devin → Devin accounts):

- Sessions are keyed by their internal organization ID, so two profiles signed in to the same org collapse into one
  account and different orgs become separate accounts.
- A refreshed browser session updates the stored token in place; a signed-out profile's account is removed on the next
  scan. Manually pasted accounts are never removed.
- Removing an auto-imported account hides it permanently (recorded under
  `hiddenTokenAccountExternalIdentifiers` in config) instead of reappearing on the next scan.
- Each account carries its own organization (`organizations/<id>` or `org/<slug>`), shown as the optional Org ID field.
- If a stored token is rejected, CodexBar re-imports the matching browser session once and retries automatically.

Accounts work with the standard multi-account surfaces: stacked/switcher menu display, parallel refresh, and the CLI
`--account`, `--account-index`, and `--all-accounts` flags.

## Manual Auth

Set **Auth source** to **Manual**, then paste either the bare token or the full `Authorization: Bearer ...` header value
from an app.devin.ai API request. The optional organization field accepts a slug, an internal `org_...` ID, or the full
organization URL.

Environment overrides:

- `DEVIN_BEARER_TOKEN` or `DEVIN_AUTHORIZATION`
- `DEVIN_ORGANIZATION` or `DEVIN_ORG`

## Data Source

CodexBar requests:

```text
GET https://app.devin.ai/api/<internal-org-id>/billing/quota/usage
```

The response supplies daily and weekly usage percentages plus reset timestamps. If Devin changes or expires a browser
session, the next refresh re-imports the session and retries once; otherwise sign in again and refresh CodexBar.
