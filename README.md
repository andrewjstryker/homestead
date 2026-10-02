# Homestead

Homestead builds and installs home configuration through GNU Make and a POSIX
shell collection driver. Each **module** owns related files and application
build rules. Homestead supplies staging, installation, conservative removal,
and coordination across modules.

## Installation

Keep a pinned checkout of Homestead at `_homestead/` in your project, either as
a Git submodule or a local checkout. No global installation is required. A
module's Makefile includes the protocol directly:

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

Tests use temporary directories without network access or installation into
your home. They require GNU-compatible `chmod --reference`, `find -mindepth`,
`stat -c`, and `cp -p`. Lint additionally requires ShellCheck. Application tests
belong to the module or configuration collection.
