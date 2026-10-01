# Engineering Workflow

VeriTrace is built by a small team: one developer owns the backend, platform, and documentation
repositories, and one owns the three frontend repositories. The workflow stays light so the effort goes into
the product. The frontend repositories follow their owner's workflow.

## 1. Branches and pull requests

- `develop` collects finished work. `main` receives a release when the team decides to make one.
- Work happens on a branch from `develop`, for example `feat/tenant-isolation`, and returns through a pull
  request. GitHub proposes `main` as the base, so pick `develop` (`gh pr create --base develop`).
- Merge when CI is green. Squash and merge commits are both fine: a merge commit keeps a branch's commits
  when they are already tidy, and squash suits branches full of throwaway commits.
- Commit messages and pull request titles follow [Conventional Commits](https://www.conventionalcommits.org/),
  for example `feat(auth): rotate refresh tokens`.

## 2. Definition of Done

A story is done when all of the following hold:

1. **Behavior** matches the domain documents and the OpenAPI or messaging contracts.
2. **Tests:**
   - unit tests cover domain logic and edge cases (≥ 80% of statements in domain packages);
   - integration tests cover persistence, RLS isolation, and messaging paths.
3. **Quality:** `make lint test` passes locally and CI is green.
4. **Security:**
   - no secrets in code or logs;
   - tenant isolation goes through the transaction helper;
   - authorization goes through the policy.
5. **Docs:** contracts (migrations, OpenAPI, messaging), ADRs (if a decision changed), and the
   [roadmap](../roadmap.md) status change together with the code.

## 3. Shared code across service repositories

- The Go platform packages (`internal/platform/…`, `internal/httpapi`) are duplicated on purpose in each
  service repository. There is no shared module to version.
- A change to them is applied to every service in the same step.
  `make check-drift` in `veritrace` reports any divergence between sibling checkouts.
- Shared test data (GS1 vectors, and later canonical-JSON, Merkle, and label-signature vectors) lives
  in `veritrace/docs/contracts/test-vectors/`. Each service copies what it uses into its
  own `testdata/` and must not modify the copy.

## 4. Repository settings

`scripts/github-settings.sh` in this repository keeps the backend, platform, and documentation repositories
alike: description, topics, merge options, `main` as the default branch, security features, and a ruleset
that accepts changes to `main` and `develop` only through pull requests. Preview it with
`make github-settings` and apply it with `scripts/github-settings.sh --apply`.

## 5. Releases

- A release merges `develop` into `main` with a merge commit, so `main` keeps the history of `develop` and
  later releases merge without conflicts.
- Milestone releases are tagged: `v1.0.0` for **M1 — Operational Core** and `v2.0.0` for
  **M2 — Decentralized Trust**.
