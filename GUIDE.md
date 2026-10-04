# Using Homestead

This guide starts with one module and then adds templates, custom builds, and
a collection. The [contract](CONTRACT.md) defines the interfaces used here.

## 1. Create a module

A module is a directory for related configuration. Keep a pinned Homestead
checkout at `_homestead/`, then create this layout:

```text
example/
  Makefile
  _homestead/
  src/config/example/settings
```

Start with this Makefile:

```make
include _homestead/homestead.mk
```

Put your application's settings in `src/config/example/settings`. Homestead
copies it to `stage/config/example/settings` and installs it beneath
`XDG_CONFIG_HOME`. See [destination defaults](CONTRACT.md#declarations) for all
namespaces. Executable scripts go under `src/bin/`; mark them executable in Git.

Add `stage/` and `.homestead/` to `.gitignore`. Stage is generated build state;
`.homestead/` holds local installation receipts. Keep those receipts on disk so
Homestead can later remove files it installed.

Pinned third-party files that are already ready to install go under matching
`vendor/` namespaces. For example, `vendor/config/example/plugin.lua` installs
alongside your settings without being copied into stage. A source directory
with a hidden `.keep` declares an empty installed directory.

## 2. Check and install

From the module directory:

```sh
make show
make check
make preview
make install
```

`show` displays resolved values and destinations. `check` diagnoses declarations,
inputs, and tool requirements without building. `preview` builds locally and
shows the proposed installation. Each action checks its own prerequisites, so
you can stage even when an installation tool is missing.

To try installation under a temporary destination:

```sh
make install DESTDIR=/tmp/homestead-install
```

This prefixes installation writes, including receipts, while preserving embedded
paths. It still uses the module's normal staging directory.

`make clean` removes staging. `make uninstall` uses the receipt to remove files
whose contents still match the latest installation; it leaves modified files
alone. For a temporary installation, use the same `DESTDIR` when uninstalling.
See the [ownership guarantees](CONTRACT.md#installation-and-removal) for failure
and removal behavior.

## 3. Render a template

Replace the Makefile with:

```make
required_inputs := EMAIL
EDITOR ?= vi
m4_vars += EDITOR
include _homestead/homestead.mk
```

Create `src/config/example/settings.m4` and remove the plain `settings` source
so that only one source declares that output:

```text
email=M4_EMAIL
editor=M4_EDITOR
```

Supply the required value when building:

```sh
make stage EMAIL=person@example.com
```

The result is `stage/config/example/settings`. Required inputs and names listed
in `m4_vars` become `M4_NAME` macros. Changes to those values trigger rendering.
Use uppercase for caller inputs and `?=` for their defaults; lowercase lists
such as `required_inputs` describe the module.

Other template files need explicit Make dependencies. Resolve build-time values
while staging and keep session-dependent values for application runtime.

## 4. Add another transformation

For Fennel-to-Lua compilation, install Fennel and create
`src/config/nvim/init.fnl`. This complete Makefile replaces the default handling
of that source:

```make
FENNEL ?= $(shell command -v fennel)
claimed_sources := src/config/nvim/init.fnl
claimed_outputs := stage/config/nvim/init.lua
stage_tools += FENNEL
include _homestead/homestead.mk

stage/config/nvim/init.lua: src/config/nvim/init.fnl
	'${FENNEL}' --compile '$<' > '$@'
	chmod 0600 '$@'
```

For a small test input, use `{:answer 42}`. Run `make check`, then `make stage`.
The `.fnl` file stays an input; the generated `.lua` joins the normal installation
manifest. Homestead creates the public output's parent directory before the
recipe runs. No change to the driver is needed.

Add dependencies for imported macros or other compile-time files. Compiler flags
and other non-file inputs need your own rebuild tracking; m4's tracking does not
extend automatically to another compiler. Keep intermediates under
`stage/.build/`. Intermediate recipes that write there need an order-only
`prune` dependency so they run after preflight. See
[extension requirements](CONTRACT.md#extensions) for ordering and failure rules.

## 5. Coordinate a collection

Move the shared Homestead checkout to the collection root:

```text
collection/
  _homestead/
  base/Makefile
  nvim/Makefile
  zsh/Makefile
```

Each module now includes `../_homestead/homestead.mk`. Modules do not locate or
call the driver. From the collection root, run:

```sh
_homestead/home check
_homestead/home preview
_homestead/home install
_homestead/home install nvim
```

The driver discovers child directories containing a Makefile. Names beginning
with `_` or `.` are excluded, keeping the dependency out of the selection. Use
`--root DIR` before the verb when invoking it elsewhere. Collection `.env` files
can supply input defaults as `NAME=value`; existing environment values win.

If your modules contribute shell environment fragments, put them under
`src/config/env.d/` or `vendor/config/env.d/`. Name shared environment providers
in `MODULES_FIRST` and consumers in `MODULES_LAST`; both accept newline-separated
names and otherwise default to empty. A collection-owned `home` wrapper can set
that policy:

```sh
#!/bin/sh
set -eu
root=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
export MODULES_FIRST="${MODULES_FIRST-base}"
export MODULES_LAST="${MODULES_LAST-zsh}"
exec "$root/_homestead/home" --root "$root" "$@"
```

Make the wrapper executable. During composing actions, consumers receive ordered
fragment paths in `ENV_FRAGMENTS`. The consumer owns assembly, rebuild tracking,
and runtime evaluation; the driver does not source the fragments. Shared values
belong to first modules, domain additions to middle modules, and assembly to
last modules. See the [composition contract](CONTRACT.md#collection-composition).

Use `./home apply` when the collection should install everything and then run
module-defined synchronization. Use `./home test` for optional module tests.
Run `./home help` for command usage.

## Troubleshooting

- **Missing input or tool:** use `make show` to inspect resolved values. Supply
  required inputs and install tools for the phase you intend to run. Full
  `check` also reports tools needed only by other phases.
- **Duplicate output:** remove overlapping plain/template declarations, claim
  custom inputs, or resolve staged/vendor overlaps.
- **Undeclared staged output:** add it to `claimed_outputs`, or put an
  intermediate in private build space.
- **Unexpected build order:** add explicit dependencies. Two prerequisites of
  the same target can run in parallel.
- **Missing receipt:** an installation must succeed to record ownership. Keep
  the receipt across source changes and cleanup; uninstall cannot reconstruct it.

Installation can leave partial writes on failure. Fix the cause before retrying;
there is no rollback. Collection failure policies are defined in the
[contract](CONTRACT.md#collection-failures).
