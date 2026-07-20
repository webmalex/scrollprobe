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
header with a blank line.

## Installing the commit hook

Install the repository-managed `commit-msg` hook after cloning:

```sh
make hooks
```

This invokes `/opt/homebrew/bin/pre-commit`. The hook validates every new
commit message before Git records the commit.
