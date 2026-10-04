# Extraction and migration

Homestead was extracted from two local implementations:

- Configuration collection `protocol`, commit
  `06b6938114a3c1603da42db14a4bd889d0f408c6`: collection driver, specification,
  helpers, and collection fixtures.
- Neovim configuration `nvim`, commit
  `5b250c021b242d6ba8fa98381bd475bf754363b2`: Make implementation and lifecycle
  tests, including fixes for caller declarations and overrides.

The original repositories are unchanged by this extraction. The security
checkout's Makefile currently depends on `../protocol/protocol.mk`; its local
`protocol/` directory does not contain a usable implementation. The collection
records Neovim as a submodule; security is an ignored independent checkout.

## Reconciled behavior

- Tool declarations work before or after inclusion; caller lists cannot remove
  Homestead's required m4 and rsync checks.
- Caller shell settings and namespace-root overrides survive inclusion.
- `inspect` is the driver's manifest interface. The older `fragment-files`
  target remains available for callers that need only environment fragments.
- The driver root is independent of its executable directory. `_` and `.`
  directories are reserved and cannot be selected as modules.
- Default ordering lists are empty. Collection wrappers own names such as
  `base` and `zsh` as floor owners and environment consumers.
- Collection `check` now implements destination collision detection, including
  compatibility links and ancestor conflicts. This was promised in the old
  collection README but absent from its driver.
- Explicitly empty installation roots fail in both shell and Make. The driver
  no longer replaces explicitly empty environment values with `.env` defaults.

## Adopt after publishing

1. Publish this repository and select a commit to pin.
2. Add it at `_homestead/` in each independent repository. Standalone module
   Makefiles use `include _homestead/homestead.mk`; modules owned directly
   by the collection use `include ../_homestead/homestead.mk`.
3. Replace the collection's large `home` script with the wrapper in README.md.
   Retain its `base`/`zsh` ordering policy in that wrapper.
4. Run Homestead's tests, then each consumer's existing tests with its pinned
   dependency. Review `show`, `check`, `preview`, and a `DESTDIR` installation.
5. Remove superseded protocol copies only after the consuming repo passes its
   checks. Update the parent collection's Neovim submodule revision afterward.

Keep `protocol/tests/concerns.sh` with the configuration collection: it exercises
real applications and configuration, rather than Homestead's generic contract.
Homestead retains only the portable lifecycle and collection fixture suites.

## Receipt-based uninstall

Install now appends rsync MD5/path records to `RECEIPT` (default:
`.homestead/receipt` in the module directory). Add `.homestead/` to consumer
ignore rules. Existing installations have no receipt: run install once to
record the current manifest, including unchanged files. This cannot recover
paths already removed from the declaration.

Uninstall no longer stages or checks rendering inputs. Consumer uninstall hooks
must not assume generated files exist. Regular-file removal compares the latest
recorded MD5, not executable status; mode-only modifications no longer prevent
removal. Compatibility links still use the current Makefile declarations.
The driver preflights `check-uninstall-tools`; modules using a separate protocol
implementation must provide it. `check` includes the `MD5SUM` checker.

Ordering names now document runtime ownership: first modules provide the shared
floor, middle modules contribute domain environment, and last modules assemble
it. No new build or install dependency is introduced. Homestead guarantees
ordered contribution delivery; consumer tests own runtime evaluation.

## Unreleased 1.0.0: stage collects errors; installation stops

These changes refine the initial, unreleased 1.0.0 contract and do not require a
version bump. Compatibility guarantees apply to released versions.

The extracted driver originally allowed implicit middle-module failures to
warn and let installation succeed; even explicit installation failures were
aggregated while later modules continued. Now `install` and `apply` stop at
the first error, including prerequisite failures. An installation error prevents
all `apply` synchronization. Already completed writes and receipts remain.

Standalone `stage` attempts all modules with usable prerequisites and returns
nonzero for any error, even with implicit selection. Failed producers contribute
no fragments, and consumers can stage with the surviving contributions. Scripts
that previously treated a partial stage as success must handle its nonzero exit
status. Other commands keep their existing failure policies.

## Declaration validation

`check-declarations` now rejects duplicate declared file paths and file/directory
conflicts using Make variables. It runs through `check-stage-tools` before
Homestead-managed staging mutations. Modules must resolve overlaps between
plain files and templates, ordinary and claimed outputs, or staged and vendored
payloads. File ancestors and source-derived empty directories also participate.
Diagnostics, cleanup, and receipt-based uninstall remain available. These checks
remain within the unreleased 1.0.0 contract and accept the documented Make path
limitations.

## Full preflight

`check` now validates declarations, required inputs, and every phase's tool
requirements without staging or composing environment fragments. It reports
independent protocol failures together. Collection checks attempt every selected
module and return nonzero for any failure, including implicitly selected middle
modules. Successful modules still participate in destination collision checks.

Use `check` instead of the removed `check-tools` command or the now-internal
`check-declarations` target. Phase-specific Make gates remain driver interfaces;
lifecycle operations do not depend on the full check. A missing install tool
therefore does not block `stage`.

Move checks requiring generated output from `check` into the staging dependency
graph, with explicit output prerequisites, or into behavioral `test` targets.
Keep `check` extensions read-only and independent of `ENV_FRAGMENTS`.

## Module terminology

The unit previously called a concern is now a module: a directory with a
Makefile and related home configuration. Update collection environment files,
wrappers, and scripts from `CONCERNS_FIRST` / `CONCERNS_LAST` to `MODULES_FIRST` /
`MODULES_LAST`. The old variable names are no longer read. Ordering and lifecycle
behavior are unchanged; this remains part of the unreleased 1.0.0 contract.

## Shared Makefile name

The shared include is now `homestead.mk`. Update module include paths from
`_homestead/protocol.mk` to `_homestead/homestead.mk` (or the corresponding
relative path to a collection's shared checkout). The old filename is removed.

## Make dependency graph and configuration boundary

Build directories are order-only prerequisites of public outputs and are created
after staging preflight and pruning. Custom public output recipes no longer need
`mkdir -p`; private intermediates still need their own directory rules and pruning
dependencies. Discovery is captured at inclusion, so declare roots and claimed
inputs/outputs before including `homestead.mk`.

Full preflight now runs in the invoking Make graph, preserving alternate Makefile
names and target-specific inputs without a recursive Make invocation.

Helper paths derive from the included file; `PROTOCOL_MK` and `PROTOCOL_BIN` are
removed. Include `homestead.mk` directly. Receipts stay at `.homestead/receipt`;
`RECEIPT` overrides are removed. If an existing installation used another receipt
location, move that history to `.homestead/receipt` before further installation
or removal. Use XDG root variables and `BIN_DIR` instead of secondary
`config_root`/`data_root`/`state_root`/`cache_root`/`bin_root` overrides. Rename
module-owned `M4FLAGS` to `m4_flags`.
