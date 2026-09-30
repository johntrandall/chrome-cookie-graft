# chrome-cookie-graft

Copy session cookies between Chrome profiles on one Mac, while holding back the
sites that define each profile's identity.

Chrome Sync never syncs cookies. Profiles signed into the same Google account
share bookmarks, history and extensions, but each keeps an isolated cookie jar —
so every login has to be repeated per profile. That isolation is often
*load-bearing*: it is what lets several profiles hold several accounts for the
same service. This tool copies the jar without copying that.

## Why you'd want this

**The case this was built for: running several Claude accounts side by side in
one browser.**

Each Claude subscription needs its own Chrome profile, because claude.ai
identifies you by cookie — two profiles sharing a cookie jar are the *same*
Claude account, not two. So you end up with one profile per subscription.

The problem is everything else. Chrome Sync never syncs cookies, so each of
those profiles starts signed out of every other site you use — your email, your
bank, your vendor portals, the hundreds you never think about. Logging all of
them back in, per profile, is not realistic. And you cannot fix it by merging
the cookie jars, because that isolation is exactly what keeps the Claude
accounts separate.

This tool resolves the conflict by copying **everything except** the hosts that
establish identity:

- `claude.ai`, `claude.com`, `anthropic.com` go in `protect` — **never copied,
  in either direction**. Each profile stays signed in as its own Claude account.
- Everything else is copied, so every profile is already signed in to the rest
  of your web.

The result is several Claude instances, each authenticated as a different
subscription, all sitting on the same logged-in browser state. That matters most
when the Claude instances are *driving* the browser: an agent working in one
profile has your real sessions available, without any risk of it acting as —
or logging you out of — the account belonging to another profile.

`protect` is enforced, not advisory. Each target's protected rows are SHA-256
fingerprinted before and after every run; if any of them changed, that profile
is restored from its backup and the run exits non-zero.

### The same shape, other services

Nothing here is Claude-specific — `protect` takes any host list. The pattern
fits whenever profiles must hold **different accounts on one service** while
sharing everything else:

- Two accounts on the same SaaS tool, cloud console, or ad platform.
- **Work and personal profiles** that should share general logins while keeping
  separate accounts on the one or two services that matter.
- **A fresh profile** you want usable immediately, without a day of re-logins.
- **Testing profiles** needing realistic logged-in state that must never touch
  your real account on the system under test.

If you only run one profile, you do not need this.

## How it works

Cookies are copied as **ciphertext**. Chrome's `Chrome Safe Storage` Keychain key
is per-**application**, not per-profile, so a blob written by one profile
decrypts in another on the same machine. Nothing is decrypted here and no
Keychain access is required. Only `<Profile>/Cookies` is ever opened — extension
state, localStorage and IndexedDB are out of reach by construction.

## Install

```sh
brew install johntrandall/tap/chrome-cookie-graft
brew services start chrome-cookie-graft      # optional: every 5 min, debounced by min_interval_minutes
```

## Configure

`~/.config/chrome-cookie-graft/config.json` (seeded on install):

| Key | Meaning |
|---|---|
| `source` | Profile **directory** name to copy from (e.g. `Default`) |
| `targets` | Profile directory names to copy into |
| `only` | If non-empty, copy **only** hosts matching these globs |
| `protect` | Never copied, in either direction — see below |
| `exclude` | Skipped when `only` is empty |
| `stale_days` | Warn if a target has not been grafted in this long |
| `keep_backups` | Timestamped `.bak-` files kept per target |
| `min_interval_minutes` | Skip a target grafted within this many minutes (0 = off). With a frequent schedule, this is what keeps runs cheap. `--force` ignores it |

Profile directory names are not display names. `chrome://version` shows the
active one as *Profile Path*.

Patterns are globs, case-insensitive. `*.example.com` also matches
`.example.com`, which is how Chrome spells a domain cookie.

### `protect` outranks everything

A host matching `protect` is never copied — **including when `only` names it
explicitly**. An allowlist must not be able to un-protect an identity host. Each
target's protected rows are also SHA-256 fingerprinted before and after each
run; if they change at all, that target is restored from its backup and the run
exits non-zero.

## Use

```sh
chrome-cookie-graft                       # all configured targets
chrome-cookie-graft Profile\ 2            # just one
chrome-cookie-graft -n                    # dry run
chrome-cookie-graft --only '*.amazon.com' # ad-hoc allowlist
chrome-cookie-graft --print-config        # effective config after overrides
```

## Behaviour worth knowing

- **A target open in Chrome is skipped.** Chrome keeps its own in-memory jar and
  flushes it on exit, so a write underneath a loaded profile is silently lost.
  Chrome keeps **every** profile it has loaded open until the whole app quits;
  closing a profile's windows is not enough. A skip is normal and exits 0.
- **Run it often, debounce it.** Because Chrome is rarely fully quit, the
  intended schedule is every 5 minutes with `min_interval_minutes: 60`. Each run
  decides eligibility (not recently grafted, not open) *before* snapshotting the
  source, so a run with nothing to do costs one `lsof` per target and prints one
  line.
- **Newer-only.** A source row never replaces a destination row that is already
  same-or-newer, so a re-run cannot downgrade a live session.
- **Staleness warnings.** A profile you always keep open would otherwise be
  skipped forever while the job kept reporting success. After `stale_days` it
  warns and exits non-zero.

## Limits

- **Same machine only.** This moves cookies between profiles of one Chrome
  install. It is not a sync service and cannot carry state to another host.
- **Cookies only.** Logins held in `localStorage` or IndexedDB do not transfer.
- **Device-bound sessions (DBSC) do not transfer**, which is part of why Google
  hosts are excluded in the shipped example config.
- Chrome 154 keeps the database at `<Profile>/Cookies`. Older builds used
  `<Profile>/Network/Cookies`; both are probed.

## Caution

This reads and writes Chrome's own SQLite store rather than going through an
API — Chrome publishes no supported interface for this. It operates only on your
own profiles, on your own machine, needs no elevated privileges, and decrypts
nothing. Even so: it is unsupported by Chrome and could break on any update.
Backups are automatic; `keep_backups` controls how many are retained.

## License

MIT
