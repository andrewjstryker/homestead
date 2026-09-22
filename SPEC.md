# Homestead Protocol

A concern is a directory that stages, installs, and removes a related set of
home-environment files. This is the contract shared by concerns and the `home`
driver.

## Interface

| Verb | Meaning |
| --- | --- |
| `help` | List public targets; the default goal. |
| `show` | Print resolved inputs and manifest destinations without changing them. |
| `inspect` | Emit tab-separated effective manifest records without staging. |
| `fragment-files` | Compatibility projection of effective `config/env.d` source paths. |
| `stage` | Prune and incrementally realize the generated portion of the manifest. |
| `check` | Stage and run concern-defined checks. |
| `preview` | Stage, then report files install would create or overwrite. |
| `install` | Stage, then install the complete manifest. |
| `sync` | Reconcile optional live or network state; empty unless extended. |
| `apply` | Driver only: install every selected concern, then sync every selected concern. |
| `uninstall` | Remove declared links still owned and regular files matching their latest receipt MD5. |
| `clean` | Remove build artifacts, never installed paths. |
| `check-tools` | Check every declared tool requirement without running a lifecycle phase. |
| `test` | Driver-only: run a concern-owned `test` target when present. |

`apply` and `test` are driver verbs, not concern targets. Every other row is
part of the concern interface implemented or extended through `protocol.mk`.

The collection driver also provides `test`, but it is not part of the protocol
contract. It runs a concern-owned `test` target when one exists and skips that
concern when no such target is declared; the protocol does not prescribe a test
framework or test DAG.

`inspect` is the driver-facing manifest interface. Each line is tab-separated:

```text
file<TAB>mode<TAB>source<TAB>manifest-path<TAB>destination
link<TAB>-<TAB>-<TAB>manifest-path<TAB>destination<TAB>target
```

`source` is the effective staged or vendored file; `destination` is the resolved
installation path without `DESTDIR`. The driver uses these records for
composition and cross-concern collision checks. `inspect` never stages.
`fragment-files` retains the older one-path-per-line environment-fragment
projection for compatibility. Both interfaces omit private manifest entries.
Declaration paths containing whitespace are unsupported by the Make manifest;
record fields must not contain tabs or newlines.

`DESTDIR` prefixes every path written by install and uninstall. It relocates
where the protocol writes, not the content it writes or the target stored in a
compatibility link. `sync` has no staged meaning and is skipped by `apply` when
`DESTDIR` is nonempty.

`preview` is the ordinary way to inspect installation. It runs after staging
and appends `--dry-run` to the same rsync commands used by `install`. `DRY_RUN`
remains available to concern-specific live operations and compatibility
callers, but is not needed to preview the core transfer.

Preview also checks compatibility links without writing them. A collision
fails preview exactly as it would fail install.

## Declaration and manifest

`src/` is the complete first-party declaration. Every non-hidden file beneath
it maps to exactly one path beneath `stage/`:

```text
src/config/alacritty/alacritty.toml → stage/config/alacritty/alacritty.toml
src/config/profile.m4               → stage/config/profile
src/data/ssh/known_hosts            → stage/data/ssh/known_hosts
src/bin/home-backup.m4              → stage/bin/home-backup
```

A final `.m4` suffix selects rendering and is removed. Every other source is
copied. Both transformations preserve whether the owner-executable bit is set.
Installed files are private to the owner: `0600`, or `0700` when staged as
executable. Every regular source in `src/bin` must be executable.

A concern establishes roots, required inputs, and claimed sources and outputs
before including `protocol.mk`. Render values, tool lists, display values, and
compatibility links can be declared there too; these extensible values may also
be extended afterward. Claimed sources are removed from the ordinary copy/m4
partition; claimed outputs are added to the public staged manifest. The concern
owns the dependency rules for producing those outputs, declares any additional
`stage_tools`, and preserves the executable distinction. This supports
transformations such as Fennel-to-Lua without adding them to the protocol.

Before realizing an m4 output, Make runs a phony reconciliation action which
records `M4`, `M4FLAGS`, `HOME`, and every render variable in the real private
file `stage/.build/m4-context`. The render-variable set is the protocol
context—the persistent XDG roots, `BIN_DIR`, and every required staging
input—plus the concern-level `m4_vars`. Each Make variable `NAME` is defined
for ordinary rendering as `M4_NAME`. Values are read by the renderer from the
line-oriented context file rather than interpolated into a shell command, so
all characters except newline and NUL are supported, including apostrophes and
shell syntax.
`M4FLAGS` controls renderer behavior such as include paths
and does not define variables. The file is replaced only when its
content changes and is a normal prerequisite of every ordinary m4 output. Thus
declared environment changes enter Make's timestamp graph without making
generated outputs phony. Wrappers may replace the default rule with a more
specific rule and narrower context when conservative shared-context
invalidation is too broad. Other template inputs remain explicit normal
prerequisites.

Hidden source entries do not participate. Any staged path containing a
dot-prefixed directory component is private build space and is likewise
excluded from the manifest. Concerns may use it for stamps or intermediates:

```text
stage/.build/environment
stage/config/.intermediate/palette
```

A public output participates either through the ordinary source mapping or
through `claimed_outputs`. A concern with a complex dependency graph may claim
its nonstandard inputs, publish its final outputs, and use private stage paths
for intermediates.

`prune` removes public staged files and empty directories which are no longer
derivable from ordinary or claimed declarations, while leaving private paths
alone. Every public staged path has an order-only dependency on prune, so the
single Make graph completes pruning before realizing that path without making
current outputs rebuild. After every stage prerequisite completes, the stage
recipe validates closure: every declared public file and source directory must
exist, and every actual public staged file or directory must be declared or be
an ancestor of a declared output. Undeclared output fails staging before
preview or installation can transfer it. Private paths and their otherwise
empty public ancestor directories remain outside this check.

`vendor/` declares pinned third-party files that are already installation
ready. A namespace beneath it maps directly to the same destination as the
corresponding staged namespace; vendored files are not copied into `stage`.
Unmapped directories such as `vendor/build/` hold third-party build inputs and
do not participate. Hidden paths are excluded. A path may not be declared by
both `stage` and `vendor`.

The effective installation manifest is the union of generated files in
`stage/` and mapped files in `vendor/`. Deleting a source and running `stage`
removes its generated declaration; deleting a vendored file removes its direct
declaration without a staging step.

## Destination namespaces

The first component below `stage/` or `vendor/` selects its installation root:

| Namespace | Root |
| --- | --- |
| `config` | `XDG_CONFIG_HOME` |
| `data` | `XDG_DATA_HOME` |
| `state` | `XDG_STATE_HOME` |
| `cache` | `XDG_CACHE_HOME` |
| `bin` | `BIN_DIR` |

The persistent XDG roots default from `HOME`; `BIN_DIR` defaults to
`$HOME/.local/bin`. An explicitly supplied empty installation root is invalid.
`XDG_RUNTIME_DIR` is session-owned, has no fallback, and is not an installation
root.

There are no special seed or directory declarations. Data such as
`known_hosts` is an ordinary repository-owned file below `src/data`. Required
empty directories are ordinary source directories. Git cannot retain an empty
directory, so a concern may retain it with a hidden `.keep`; hidden files do
not become manifest entries.

Environment fragments are ordinary configuration:

```text
src/config/env.d/mail.sh.m4 → stage/config/env.d/mail.sh
                             → $XDG_CONFIG_HOME/env.d/mail.sh
```

The driver may pass fragments from either manifest root to a shell concern for build-time
composition. This consumer behavior does not create a second staging namespace
or installation rule.

## Installation and ownership

Installation compares content, not timestamps. For every populated namespace,
rsync reports and creates missing destinations, leaves identical files alone,
and reports and replaces different files. It preserves the declared executable
distinction while removing group and world permissions. Vendored symlinks are
installed as the regular files they resolve to.

The current manifest is the installation declaration. The receipt is the
historical record used to uninstall regular files. `RECEIPT` defaults to
`${CURDIR}/.homestead/receipt`, outside `stage`, and `clean` preserves it. A
relative override is resolved from the concern directory. Add `.homestead/` to
the concern's Git ignore rules. For a staged installation, `DESTDIR` prefixes
the absolute receipt location too, keeping staged and live histories separate.
`show` reports the effective receipt location.

For each successful namespace transfer, install appends records produced by
rsync using `--checksum-choice=md5`, repeated `--itemize-changes`, and the `%C`
checksum field. Unchanged files are included. Each record contains:

```text
md5<TAB>absolute-destination-without-DESTDIR
```

The file is created with private permissions. Paths must not contain control
characters or require rsync's `\#ooo` filename escaping. Records represent
regular files, including dereferenced vendored symlinks; directories are not
owned by the receipt. Preview and dry-run installation do not create or append
receipts. An empty successful installation creates an empty receipt.

Appending preserves older destinations when declarations or namespace roots
change. For repeated destinations, the latest record wins; a match against an
older checksum is insufficient. The receipt remains after uninstall, so
repeated uninstall is harmless. This is a sequential per-concern history;
concurrent install/uninstall operations on the same receipt are unsupported.

Uninstall validates and reads the receipt without staging, inspecting the
manifest, or requiring rendering inputs and tools. For each latest record:

- an absent destination is reported as not installed;
- a regular file with a matching MD5 is removed, regardless of permission changes;
- a different file, directory, or replacement symlink is left untouched.

`DESTDIR` prefixes recorded destinations during removal. Uninstall dry runs
report matches without removing them or changing the receipt. A missing or
malformed receipt fails before removal; deleting it loses regular-file
uninstall capability. Source deletion and `clean` do not affect that capability.
MD5 is used for content comparison, not authentication of receipt contents.

Rsync failure is reported without appending that invocation's records. Earlier
successful namespace transfers remain recorded. A failing transfer can leave
partial destination writes; there is no rollback or attempt to infer ownership
of those writes. A later receipt-write failure likewise fails installation.

Compatibility links remain owned by the Makefile declarations, separately
from receipts. Install creates a missing link, leaves the correct link alone,
and refuses to replace anything else. After processing regular files,
uninstall removes a declared link only while it still points to its declared
target. Removed or changed link declarations do not retain historical ownership.

## Wrapper Makefile interface

`PROTOCOL_MK`, the declaration roots, `required_inputs`, `claimed_sources`, and
`claimed_outputs` are established before including `protocol.mk`. Extensible
lists and rendering values may be set afterward because the protocol expands
them when used:

| Variable | Purpose |
| --- | --- |
| `PROTOCOL_MK` | Selected protocol file. |
| `src`, `stage` | First-party source and generated roots; defaults are `src`, `stage`. |
| `RECEIPT` | Append-only regular-file installation history; defaults to `${CURDIR}/.homestead/receipt`, with `DESTDIR` applied to its absolute location. |
| `MD5SUM` | MD5 checker used during uninstall; defaults to the discovered `md5sum`. |
| `vendor` | Third-party declaration root; defaults to `vendor`. |
| `claimed_sources` | First-party inputs owned by concern-specific transformations. |
| `claimed_outputs` | Public staged files produced from claimed sources. |
| `M4`, `M4FLAGS` | Renderer and behavioral arguments for ordinary templates. |
| `m4_vars` | Additional values recorded in context and defined as `M4_NAME`. |
| `stage_tools` | Tool variables which must resolve before staging mutates its output. |
| `install_tools` | Tool variables which must resolve before installation transfers files. |
| `uninstall_tools` | Additional tool variables required before uninstall; Homestead adds `MD5SUM`. |
| `sync_tools` | Tool variables which must resolve before synchronization begins. |
| `required_inputs` | Caller-supplied staging values, exported to recipes and recorded in m4 context. Missing values fail stage preflight but not help, show, clean, or tool diagnostics. |
| `show_vars` | Additional values printed by `show`. |
| `links` | Manifest paths requiring compatibility links. |
| `link_of` | Maps a manifest path to its compatibility location. |

Tool lists contain variable names, not command names. Homestead checks `M4`
when templates are present, `RSYNC` for installation, and `MD5SUM` for uninstall
in addition to caller tool lists. Wrappers may set lists before inclusion or
extend them afterward. The phase targets check only their effective lists,
while `check-tools` checks their union. Caller `SHELL`, `.SHELLFLAGS`, and
namespace roots such as `config_root` override Homestead defaults.

After including the protocol, wrappers add prerequisites or recipes to `stage`, `check`, `sync`, `clean`,
`before-uninstall`, or `after-uninstall` as needed. They may define ordinary
file rules for their derived stage paths. `claimed_outputs` is the extension
seam for public outputs that the ordinary `src` mapping cannot derive; wrappers
must not maintain another manifest beside it.

## Composition and independence

The driver scans immediate child directories containing a Makefile, excluding
names beginning with `_` or `.`. Excluded directories cannot be explicitly
selected. It accepts `--root DIR` before the verb, otherwise uses
`HOMESTEAD_ROOT` or the current working directory. Its own executable location
does not determine the collection root. It loads collection `.env` values as
data, preserving all existing environment values, including empty ones.

Collection `check` runs concern checks and inspects the successful concerns for
collisions. Equal resolved destinations and file/ancestor conflicts across
concerns, including compatibility links, are fatal regardless of selection
policy. Destinations are compared as declared paths; filesystem symlink aliases
are not resolved. Install does not implicitly invoke collection `check`.

The three concern groups express directional runtime composition:

| Group | Ownership and responsibility |
| --- | --- |
| First (`CONCERNS_FIRST`) | Own the shared runtime environment floor: variables other domains may rely on having. |
| Middle | Own their domain configuration and contribute additional environment declarations; may rely on the floor. |
| Last (`CONCERNS_LAST`) | Own assembly of the floor and contributions into a consumer's runtime environment, such as shell startup configuration. |

Concerns build and install independently: they do not inspect sibling trees or
require another concern to be installed first. This does not mean runtime
self-sufficiency or duplicating the floor. Floor owners define shared variables;
other domains use those definitions rather than restating them. Runtime
dependencies flow from the floor through domain contributions to consumers.
There is no middle-to-middle ordering contract. Multiple last concerns receive
the same preceding contribution set; they do not consume one another's output.

Both policy lists default to empty; a collection names its floor owners and
consumers. The driver filters the lists against the selection: explicitly
selecting a consumer does not automatically select a floor. Consumers own the
behavior when optional contributions are absent or they are built standalone.
First/last concerns follow their configured list order. Middle concerns retain
discovery order for implicit selection and argument order for explicit
selection, but must not depend on that incidental order.

When a last concern is selected for a composing lifecycle operation, the driver
stages preceding concerns, queries their effective `config/env.d/*.sh` paths
through `inspect`, and delivers the ordered paths as `ENV_FRAGMENTS`. All first
contributions precede all middle contributions; contents are unchanged. The
driver does not source fragments or inject their runtime variables into later
Make processes. The consumer must preserve floor-before-contribution evaluation
when assembling its runtime configuration. Homestead guarantees ordered delivery;
consumers own assembly and runtime behavior. Homestead tests delivery, while
runtime environment tests belong to the consumers or configuration collection.

Uninstall uses receipts and current link declarations directly. It does not
stage earlier concerns or collect environment fragments.

Selection also determines collection-level failure severity. An explicit
concern list is strict: every named concern must succeed. With implicit
discovery, configured first and last concerns are mandatory anchors and middle
concern failures are warnings. Failures are aggregated. A failed concern is
excluded from subsequent phases of the same command; in particular, `apply`
synchronizes only concerns whose installation succeeded. The driver treats a
concern failure as opaque: missing inputs, unavailable tools, invalid staging,
and runtime errors all use the same nonzero interface. It assigns severity from
selection context without inspecting the cause.

Installed files contain no unresolved build macros. Facts knowable on the build
host—tool paths, persistent XDG roots, and required inputs—are resolved while
staging. Runtime evaluation is reserved for session facts which cannot be known
then. Build macros use the `M4_` namespace, so runtime variables retain their
ordinary names without quoting, capture, or undefinition workarounds.

GNU Make 4.0+, a POSIX shell and utilities, m4, `md5sum`, and rsync with
`--mkpath` and `--checksum-choice=md5` support are assumed. Tests also require GNU-compatible utility options noted
in README.md. Git manages dependency checkouts but is not a lifecycle tool.
