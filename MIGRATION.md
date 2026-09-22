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
  directories are reserved and cannot be selected as concerns.
- Default ordering lists are empty. Collection wrappers own names such as
  `base` and `zsh`, as well as their required/best-effort policy.
- Collection `check` now implements destination collision detection, including
  compatibility links and ancestor conflicts. This was promised in the old
  collection README but absent from its driver.
- Explicitly empty installation roots fail in both shell and Make. The driver
  no longer replaces explicitly empty environment values with `.env` defaults.

## Adopt after publishing

1. Publish this repository and select a commit to pin.
2. Add it at `_homestead/` in each independent repository. Standalone concern
   Makefiles use `PROTOCOL_MK ?= _homestead/protocol.mk`; concerns owned directly
   by the collection use `PROTOCOL_MK ?= ../_homestead/protocol.mk`.
3. Replace the collection's large `home` script with the wrapper in README.md.
   Retain its `base`/`zsh` ordering policy in that wrapper.
4. Run Homestead's tests, then each consumer's existing tests with its pinned
   dependency. Review `show`, `check`, `preview`, and a `DESTDIR` installation.
5. Remove superseded protocol copies only after the consuming repo passes its
   checks. Update the parent collection's Neovim submodule revision afterward.

Keep `protocol/tests/concerns.sh` with the configuration collection: it exercises
real applications and configuration, rather than Homestead's generic contract.
Homestead retains only the portable lifecycle and collection fixture suites.
