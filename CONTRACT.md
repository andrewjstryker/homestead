# Homestead module contract

A Homestead module is a directory that declares and installs a related set of
home configuration files. Its Makefile includes `homestead.mk` and may extend
the build with application-specific rules. This reference defines the interface
between modules and the collection driver. Setup and examples belong in the
[guide](GUIDE.md); command usage belongs in `home help`.

## Declarations

The module chooses its protocol include path and must not invoke the driver.
Default roots are `src`, `stage`, and `vendor`. Set alternate roots and
`required_inputs`, `claimed_sources`, and `claimed_outputs` before inclusion.

Ordinary sources map to matching staged paths. A final `.m4` suffix selects
rendering and is removed; other files are copied. Claimed sources are excluded
from these rules; claimed outputs join the public staged manifest. Both lists
contain paths including their respective roots. Outputs must be known without
building and need not correspond one-to-one with inputs.

Mapped vendor files install directly. The manifest is the union of ordinary
outputs, claimed outputs, and vendored files; modules must not maintain another
installation manifest. Public paths begin with one of these namespaces:

| Namespace | Root variable | Default location |
| --- | --- | --- |
| `config` | `XDG_CONFIG_HOME` | `$HOME/.config` |
| `data` | `XDG_DATA_HOME` | `$HOME/.local/share` |
| `state` | `XDG_STATE_HOME` | `$HOME/.local/state` |
| `cache` | `XDG_CACHE_HOME` | `$HOME/.cache` |
| `bin` | `BIN_DIR` | `$HOME/.local/bin` |

Explicitly empty roots are invalid. `XDG_RUNTIME_DIR` is not an installation
root. Source directories declare directories, including empty ones. Hidden
source/vendor paths and files ending in `~`, `.orig`, or `.rej` are excluded from
ordinary discovery. Dot-prefixed staged paths are private build space.
Declaration paths cannot contain whitespace or Make pattern/syntax characters.
Files in `src/bin` must be executable; installed files receive `0600` or `0700`.

## Inputs

Caller inputs use uppercase names with `?=` for defaults; module declarations
use lowercase names. `required_inputs` names nonempty staging values exported
to recipes. Tool lists `stage_tools`, `install_tools`, `sync_tools`, and
`uninstall_tools` name tool variables, not commands. The protocol adds `M4` for
ordinary templates, `RSYNC` for installation, and `MD5SUM` for removal. Tool
gates require nonempty values; executable capabilities are module-owned checks.

Ordinary m4 outputs receive persistent XDG roots, `BIN_DIR`, required inputs,
and names in `m4_vars` as `M4_NAME`. Changes to these values or renderer settings
invalidate those outputs. Other file dependencies remain explicit. Render values
cannot contain newline or NUL. `show_vars` adds named values to diagnostics.

## Targets and extensions

The protocol supplies `help`, `show`, `check`, `stage`, `preview`, `install`,
`sync`, `uninstall`, and `clean`. Their required lifecycle behavior is below.
`apply` is driver-owned; `test` is an optional module target run by the driver.

`check` is read-only preflight covering declarations, required inputs, all phase
tools, and module checks. It must not stage. Actions depend only on their own
requirements; they do not implicitly run full `check`. Independent protocol
preflight failures are reported together, with a nonzero result if any fail.

Staging validates declarations, prunes obsolete public outputs, builds declared
files, and validates the resulting public tree. Duplicate files and file/directory
conflicts are invalid. Declared files and source directories must exist; actual
public files must be declared, and public directories must be declared or
ancestors of outputs. Private paths and their otherwise empty ancestors are exempt.

### Extensions

Extend lifecycle targets with prerequisites and preserve protocol recipes.
Declared public output recipes run after `prune` through order-only dependencies;
`prune` depends on staging preflight. Module-owned intermediate recipes and
other staging mutations must also depend on `prune`. Sibling prerequisites have
no ordering guarantee.

Custom transformations own complete dependency tracking, including imported
files and changes to compiler settings, and must fail when generation fails.
They must create parent directories and set the output's executable distinction.
The protocol enables `.DELETE_ON_ERROR` for changed outputs of failed recipes.

Output validation belongs in staging rules with explicit output dependencies.
Behavioral tests belong in `test`. Checks required by an action must gate that
action as well as `check`. `sync` may supply a recipe and must honor `DRY_RUN`.
Uninstall hooks run `before-uninstall` → removal → `after-uninstall`, without
staging. `links` lists manifest paths requiring compatibility links; `link_of`
maps each to its location, defaulting to `${HOME}/.<basename>`.

## Installation and removal

Installation compares content and preserves destinations outside the manifest.
Vendored symlinks install as regular files. Successful namespace transfers append
ownership records, including unchanged files, to `.homestead/receipt` by default.
Uninstall uses the latest MD5 per destination without staging: matching regular
files are removed, while modified files and replacement symlinks are preserved.
Directories are not receipt-owned. Missing or malformed receipts fail removal;
receipts survive uninstall and cleanup. Compatibility links are removed only
while they match current declarations; their ownership has no historical record.

Failed transfers may leave unrecorded partial writes; previous successful
transfers remain recorded. There is no rollback. Concurrent install/uninstall
against the same receipt is unsupported. Recorded paths must not contain control
characters or require rsync filename escaping. `clean` removes staging only.

Preview and dry-run installation may stage but do not write destinations or
receipts. `DESTDIR` prefixes installation/removal destinations and receipt paths,
not local staging, embedded values, or link targets. The driver rejects staged
`sync` and skips synchronization during staged `apply`.

## Driver interfaces

The driver requires `check-stage-tools` (declarations, required inputs, staging
tools), `check-install-tools`, `check-sync-tools`, and `check-uninstall-tools`.
These targets must not run lifecycle actions. It also requires read-only
`inspect`, which emits tab-separated records, excluding private paths:

```text
file<TAB>mode<TAB>source<TAB>manifest-path<TAB>destination
link<TAB>-<TAB>-<TAB>manifest-path<TAB>destination<TAB>target
```

Destinations exclude `DESTDIR`; sources may not exist before staging. Modes are
`0600` or `0700`; an unbuilt claimed output reports `0600`. Fields cannot contain
tabs or newlines. `fragment-files` remains a compatibility projection of effective
environment-fragment source paths, one per line.

The driver discovers immediate child directories containing a Makefile, excluding
names beginning with `_` or `.`. Modules must build independently without
inspecting siblings. Collection `check` compares successful modules' declared
destinations for equal-path and file/ancestor collisions, including links.
Paths are compared as declared, without resolving filesystem aliases.

## Collection composition

`MODULES_FIRST` names shared environment providers; middle modules contribute
domain configuration; `MODULES_LAST` names consumers. Both lists default to
empty and contain newline-separated names. First/last follow configured order;
middle modules have no ordering dependency on one another.

During `stage`, `preview`, `install`, and `apply`, the driver stages selected
preceding modules and passes absolute `config/env.d/*.sh` paths from stage or
vendor as newline-separated `ENV_FRAGMENTS`. First contributions precede middle
contributions. Consumers own assembly, dependency tracking, and ordered runtime
evaluation. Multiple consumers receive the same preceding set. Selection does
not add missing providers; consumers own standalone behavior. Other actions do
not compose. The driver does not evaluate fragments.

## Collection failures

`check` and `stage` collect errors and fail for any selected module's failure.
Stage excludes failed producers from composition and stages successful producers
once; surviving contributions do not imply a complete runtime environment.
`install` and `apply` preflight staging and installation across the selection
before building, and stop on the first failure. Apply syncs only after all
installations succeed and synchronization preflight passes.

Other commands treat explicit selections and first/last modules as required;
implicitly selected middle-module failures are warnings. Fatal failures stop
subsequent phases. Dry-run and `DESTDIR` operations retain the same policies.
