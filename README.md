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
make uninstall            # remove files still matching the current manifest
```

Use `make install DESTDIR=/tmp/homestead-install` to prefix installation writes
without changing embedded paths. `preview` and dry-run installation still build
local staged files. Uninstall leaves modified installed files in place.

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

Requirements: GNU Make 4.0+, POSIX shell and utilities, m4, and rsync with
`--mkpath` support. The test suite also uses GNU-compatible `chmod --reference`,
`find -mindepth`, and `cp -p`. Git is needed to manage dependency checkouts.

```sh
make test                 # isolated staging and collection fixture suites
make lint                 # shell syntax and ShellCheck (installed separately)
```

Tests run entirely in temporary directories and do not contact the network or
install into the user's home. Application-specific behavioral tests belong to
consumers; they are not part of Homestead's release suite.
