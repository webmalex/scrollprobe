# Contributing

## Commit messages

This repository uses a strict subset of
[Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/):

```text
type(scope): summary
```

The scope is optional. Use one of these types:

- `feat` for a user-visible capability;
- `fix` for a bug fix;
- `docs` for documentation only;
- `refactor` for an internal change without new behavior or a bug fix;
- `test` for tests only;
- `build` for the build or packaging system;
- `ci` for continuous integration;
- `chore` for repository maintenance;
- `perf` for a performance improvement;
- `revert` for reverting an earlier change.

Write the summary in English, in the imperative mood, starting with a lowercase
letter. Keep the complete header at 72 characters or fewer and do not end it
with punctuation. Use a lowercase `kebab-case` scope when one helps identify
the affected area.

Examples:

```text
feat(protection): recover disabled event taps
fix(packaging): preserve the app designated requirement
docs: document the guest installation flow
```

For an incompatible change, add `!` before the colon and explain the impact in
a `BREAKING CHANGE:` footer. Separate an optional body and footer from the
header with a blank line. Use the body to explain motivation, constraints and
non-obvious consequences rather than repeating the diff. Wrap prose when it is
practical, but do not wrap URLs, commands or structured trailers solely to meet
a line-length target.

Use standard trailers such as `Refs:`, `Fixes:` and `Co-authored-by:` when they
apply. Keep commits atomic: each commit should represent one coherent change
and leave the repository in a usable state. Merge, `fixup!` and `squash!`
commits must not remain in the published branch.

## Installing the hooks

Install the repository-managed `pre-commit` and `commit-msg` hooks after
cloning. The `pre-commit` executable must be available through `PATH`:

```sh
make hooks
```

Set `PRE_COMMIT` when a non-standard executable name or path is required, for
example `make PRE_COMMIT=/custom/path/pre-commit hooks`. The `commit-msg` hooks
validate Conventional Commits syntax and repository-specific title style. The
`pre-commit` hooks check whitespace, file endings, YAML, JSON and XML syntax,
merge markers, large files, filename conflicts, private keys, symlinks,
submodules and executable scripts.

Run every file check explicitly with:

```sh
make lint
```

Local hooks can be bypassed with `--no-verify`, so the same checks should run in
CI when the repository gains a publication workflow.
