# Homestead

Homestead builds and installs home configuration through GNU Make and a POSIX
shell collection driver. Each **module** owns related files and application
build rules. Homestead supplies staging, installation, conservative removal,
and coordination across modules.

## Installation

Keep a pinned checkout of Homestead at `_homestead/` in your project, either as
a Git submodule or a local checkout. No global installation is required. A
module's Makefile includes Homestead directly:

```make
include _homestead/homestead.mk
```

Put configuration in `src/config/`; for example, `src/config/example/settings`
installs to `$HOME/.config/example/settings` by default. From the module:

```sh
make check
make preview
make install
```

Requirements are GNU Make 4.0+, a POSIX shell and utilities, m4 for templates,
`md5sum` for removal, and rsync supporting `--mkpath` and
`--checksum-choice=md5` for installation. Custom transformations require their
own tools. Git is only needed to manage dependency checkouts.

## Documentation

- [Guide](GUIDE.md): set up a module, render templates, add transformations,
  and coordinate a collection.
- [Contract](CONTRACT.md): module interfaces, declarations, extension rules,
  and lifecycle guarantees.
- [Migration notes](MIGRATION.md): extraction history and changes for existing
  consumers.

Run `make help` in a module or `_homestead/home help` for command usage.

## Development

```sh
make test
make lint
```

Tests require Bats Core (1.10+) and Bash in addition to the runtime tools.
Each case uses its own temporary directory and isolated home/XDG roots, without
network access. They also require GNU-compatible `chmod --reference`,
`find -mindepth`, `stat -c`, `touch -t`, and `cp -p`. Lint requires ShellCheck.

Run a file or select named behaviors with:

```sh
make test TESTS=tests/receipts.bats
make test BATS_FLAGS='--filter preflight'
```

Tests cover Homestead's declarations, dependency graph, lifecycle safety,
receipts, and collection policies. Keep a case when a plausible change to
Homestead could break the behavior it asserts. Use real Make and rsync for
integration boundaries; use controlled failures to exercise our error handling.
Avoid duplicating tool semantics or checking private implementation details
when an observable result can establish the guarantee. Application tests belong
to the module or configuration collection.

CI runs `make lint` and `make test` on Ubuntu 24.04 for every pull request to
`main` and every push to `main`. Repository maintainers can find branch protection
setup in the [administration guide](.github/README.md).
