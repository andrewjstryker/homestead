# Homestead

Homestead builds and installs home configuration through a shared GNU Make
lifecycle and a POSIX shell collection driver. Each **concern** owns its files,
application-specific build rules, checks, and optional runtime synchronization.
Homestead owns staging, installation, conservative removal, and coordination.

The full contract is in [SPEC.md](SPEC.md). Extraction history and consumer
migration notes are in [MIGRATION.md](MIGRATION.md).

## A standalone concern

Keep a pinned checkout of Homestead at `_homestead/` (for example, a Git
submodule). Declare files under `src/config`, `src/data`, `src/state`,
`src/cache`, or `src/bin`, then include the shared lifecycle:

```make
required_inputs := EMAIL
m4_vars += EDITOR

PROTOCOL_MK ?= _homestead/protocol.mk
include ${PROTOCOL_MK}
```

Ordinary files are copied into `stage/`. A final `.m4` suffix selects rendering
and is removed. Templates receive declared Make values as `M4_NAME`. Pinned,
installation-ready third-party files under matching `vendor/` namespaces join
the manifest directly; `vendor/build/` remains private build input.

```sh
make show                 # resolved values and destinations
make check                # stage and run concern checks
make preview              # stage, then preview destination changes
make install              # stage and install
make sync                 # optional application-owned live work
make uninstall            # remove files matching their latest receipt MD5
```

Use `make install DESTDIR=/tmp/homestead-install` to prefix installation writes
without changing embedded paths. `preview` and dry-run installation still build
local staged files. Uninstall leaves content-modified installed files in place.

Install appends rsync-produced MD5 checksums and destination paths to
`.homestead/receipt` in the concern directory, including unchanged files.
`RECEIPT` overrides this location. Keep it out of Git; `clean` preserves it.
`DESTDIR` prefixes its absolute location as well as payload paths, so staged
installs have separate receipts. `make show` displays the effective location.

Uninstall uses the latest record for each destination without rebuilding stage.
It works after sources are removed or destination roots change, provided the
same receipt remains available. It removes matching regular files even if their
permissions changed, leaves mismatches and replacement symlinks alone, and
retains the receipt. Missing or malformed receipts fail before removal.
Compatibility links are removed only when they match the current Makefile
declarations. Dry runs leave receipts unchanged.

Records are appended after each successful namespace transfer. A failed rsync
invocation may leave partial writes but contributes no receipt records; earlier
successful transfers remain recorded. There is no rollback. Use one install or
uninstall at a time per receipt. Full details are in [SPEC.md](SPEC.md#installation-and-ownership).

## A collection

```text
collection/
  home                    # small collection-owned wrapper
  _homestead/             # pinned Homestead dependency
  base/Makefile
  nvim/Makefile
  zsh/Makefile
```

The driver discovers immediate child directories containing a `Makefile`,
including symlinked directories. Names beginning with `_` or `.` are excluded,
even when explicitly requested. This keeps infrastructure such as `_homestead`
out of concern discovery.

A collection-owned wrapper can supply policy:

```sh
#!/bin/sh
set -eu
root=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
export CONCERNS_FIRST="${CONCERNS_FIRST-base}"
export CONCERNS_LAST="${CONCERNS_LAST-zsh}"
exec "$root/_homestead/home" --root "$root" "$@"
```

First, middle, and last describe runtime environment ownership:

- **First concerns own the floor:** shared environment variables other domains
  can rely on at runtime, without each domain recreating their definitions.
- **Middle concerns own domain configuration and contributions:** they may rely
  on the floor, but not on ordering among their peers.
- **Last concerns own assembly:** they receive floor fragments followed by
  domain contributions and assemble a shell or other consumer environment.

This is a runtime dependency, not a build or installation dependency. Homestead
passes ordered fragment paths without evaluating their contents. Consumers own
assembly and must preserve floor-before-contribution evaluation. Multiple last
concerns receive the same contribution set. Tests of the assembled environment
belong to the consumer or configuration collection.

Homestead itself assigns no special concern names. `CONCERNS_FIRST` and
`CONCERNS_LAST` default to empty and accept newline-separated lists. Explicit
selection is strict. With implicit selection, first/last concerns are required
and middle concerns are best-effort; their failures produce warnings. Configure
these lists deliberately if a collection must fail when its essential concerns
fail. A failed concern is excluded from subsequent phases.

```sh
./home show
./home check              # concern checks plus destination collision checks
./home apply --dry-run
./home apply              # install all selected concerns, then sync successes
./home install nvim zsh
./home test                # run optional concern-owned test targets
```

Invoke the driver directly with `_homestead/home --root /path/to/collection
show`. Root selection is `--root`, then `HOMESTEAD_ROOT`, then the current working
directory. `--root` must precede the verb. No dependency path is automatically
forced on concerns: each concern selects its own pinned `PROTOCOL_MK`.

The collection `.env` supplies `NAME=value` defaults without executing shell
code. Existing environment values, including empty values, take precedence.
Unset XDG roots receive conventional defaults; explicitly empty roots fail.

`check` rejects shared resolved destinations and file/ancestor conflicts across
successful concerns, including compatibility links. These conflicts are fatal
with either explicit or implicit selection. Install does not implicitly run
`check`; review a collection with `check` and `preview` before installation.

The driver queries the read-only `inspect` target for manifest records. It
passes staged or vendored `config/env.d/*.sh` paths to configured last concerns
as `ENV_FRAGMENTS`. `fragment-files` remains a compatibility projection.

## Development

Requirements: GNU Make 4.0+, POSIX shell and utilities, m4, `md5sum`, and rsync
with `--mkpath` and `--checksum-choice=md5` support. The test suite also uses GNU-compatible `chmod --reference`,
`find -mindepth`, `stat -c`, and `cp -p`. Git is needed to manage dependency checkouts.

```sh
make test                 # isolated staging, collection, and receipt suites
make lint                 # shell syntax and ShellCheck (installed separately)
```

Tests run entirely in temporary directories and do not contact the network or
install into the user's home. Application-specific behavioral tests belong to
consumers; they are not part of Homestead's release suite.
