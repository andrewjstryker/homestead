# Repository administration

The [CI workflow](workflows/ci.yml) runs `make lint` and `make test` on Ubuntu 24.04 for every pull request to
`main` and every push to `main`. The single required check is **Tests and lint**;
keep that job name stable because the branch rules refer to it. All changes,
including documentation, run the check so a required workflow cannot be skipped
by path filters.

The main-branch policy is defined in [the ruleset](main-ruleset.json):
changes require a pull request, passing checks from GitHub Actions, an up-to-date
branch, and resolved review conversations. No reviewer approval is required,
so a sole maintainer can merge their own pull requests. Force pushes and deletion
are blocked, with no bypass actors. A multi-platform matrix and coverage quota
are unnecessary until the project has additional supported environments or a
specific coverage need.

The workflow file runs CI; the ruleset must also be enabled on GitHub to gate
merges. For a new repository, publish the initial `main` and let CI pass first.
Then import `.github/main-ruleset.json` in **Settings → Rules → Rulesets → New
ruleset → Import a ruleset**, or, from the repository root, create it once with:

```sh
gh api --method POST repos/andrewjstryker/homestead/rulesets \
  --input .github/main-ruleset.json
```

Subsequent edits to the JSON do not automatically update the GitHub ruleset.
