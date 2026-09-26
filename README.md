# chrome-cookie-graft

Copy session cookies between Chrome profiles on one Mac, while holding back the
sites that define each profile's identity.

Chrome Sync never syncs cookies. Profiles signed into the same Google account
share bookmarks, history and extensions, but each keeps an isolated cookie jar —
so every login has to be repeated per profile. That isolation is often
*load-bearing*: it is what lets several profiles hold several accounts for the
same service. This tool copies the jar without copying that.

## Why you'd want this

You keep several Chrome profiles on one Mac, and you want them to share your
logins — but not *all* of them.

The motivating case is **running more than one account on the same service**.
Chrome's per-profile cookie isolation is what makes that possible, so you cannot
simply merge the jars. But that same isolation also means every profile starts
logged out of the several hundred *other* sites you use, and logging back in
profile-by-profile is not realistic.

Concretely, this was written for driving browser automation across a set of
profiles that each hold a different account on one service, where:

- each profile must stay signed in as **its own** account on that service, and
- every profile should already be signed in to everything **else** — your email,
  your bank, your vendor portals, the hundred sites you never think about.

`protect` is the whole point: those identity-defining hosts are never copied, in
either direction, and the tool verifies afterwards that they did not move. The
rest of the jar is shared.

Other situations with the same shape:

- **Work and personal profiles** that should share your general logins while
  keeping separate accounts on the one or two services that matter.
- **A fresh profile** you want usable immediately, without a day of re-logins.
- **Testing profiles** that need a realistic logged-in state but must never
  touch your real account on the system under test.

If you only need one profile signed in, you do not need this. If you have never
hit the "I am logged out again in this profile" problem, you do not need this
either.

## How it works

Cookies are copied as **ciphertext**. Chrome's `Chrome Safe Storage` Keychain key
is per-**application**, not per-profile, so a blob written by one profile
decrypts in another on the same machine. Nothing is decrypted here and no
Keychain access is required. Only `<Profile>/Cookies` is ever opened — extension
state, localStorage and IndexedDB are out of reach by construction.

## Install

```sh
brew install johntrandall/tap/chrome-cookie-graft
brew services start chrome-cookie-graft      # optional: daily run
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
  Close the profile's windows and re-run. Exit 1 means at least one skip.
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
