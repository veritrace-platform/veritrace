# Engineering Workflow

## 1. Branches

| Branch | Purpose | Merges from |
| --- | --- | --- |
| `main` | Released code only; the default branch visitors see | `develop` (release PR, merge commit) |
| `develop` | Integration branch; always builds and passes CI | Work branches |
| `feat/<slug>` | New behavior, for example `feat/tenant-isolation` | — |
| `fix/<slug>` | Bug fix | — |
| `docs/<slug>`, `chore/<slug>`, `refactor/<slug>`, `test/<slug>`, `ci/<slug>` | Non-functional changes | — |

- Work branches start from `develop` and return to it through a pull request.
- `main` and `develop` are protected: changes arrive only through pull requests, and CI must be green
  before merging.
- `main` is the default branch, so GitHub proposes `main` as the base of a new pull request. **Work
  pull requests must target `develop` explicitly** (in the UI, or with `gh pr create --base develop`).

## 2. Commits

The format is [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <imperative summary, lower case, no period, ≤ 72 chars>

<optional body: what and why, wrapped at 72>

<optional footer: BREAKING CHANGE: …>
```

- **Types:** `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `ci`, `build`, `perf`.
- **Scopes:** a domain or area of the repository, such as `auth`, `tenancy`, `gs1`, `shipments`,
  `handover`, `recall`, `ingest`, `detector`, `ws`, `relayer`, `compose`, `docs`.
- One logical change per commit, and the build passes at every commit.

## 3. Pull requests

- Keep each pull request to one coherent change. It should be reviewable in about 30 minutes.
- The title is required and follows the commit format. The description is optional; add one when the
  change needs context that the title and commits do not give.
- **Work pull requests** (work branch → `develop`) are merged by **squash**. The pull request title
  becomes the commit message, so the title follows the commit format.
- **Release pull requests** (`develop` → `main`) are merged with a **merge commit**, never squash or
  rebase. The history of `develop` then stays contained in `main`, so later releases merge without
  conflicts.
- Multi-commit bootstrap branches that are already curated (for example an initial setup) may also be
  merged into `develop` with a merge commit, to keep their individual commits.
- A change that touches a contract (migration, OpenAPI, messaging document, ADR) updates it in the same
  pull request. A cross-repository contract change links the counterpart pull request.

## 4. Definition of Done

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
5. **Docs:** contracts, ADRs (if a decision changed), and the [roadmap](../roadmap.md) status are updated.

## 5. Shared code across service repositories

- The Go platform packages (`internal/platform/…`, `internal/httpapi`) are duplicated on purpose in each
  service repository. There is no shared module to version.
- A change to them is applied to every service in the same step.
  `make check-drift` in `veritrace` reports any divergence between sibling checkouts.
- Shared test data (GS1 vectors, and later canonical-JSON, Merkle, and label-signature vectors) lives
  in `veritrace/docs/contracts/test-vectors/`. Each service copies what it uses into its
  own `testdata/` and must not modify the copy.

## 6. Repository settings (GitHub)

Every repository uses the same settings. They are declared in `scripts/github-settings.sh` in this
repository (description, homepage, topics, merge options, default branch, security features, and a
ruleset protecting `main` and `develop`), and applied with `scripts/github-settings.sh --apply` once
both branches exist:

| Setting | Value |
| --- | --- |
| Default branch | `main` (what visitors see); work targets `develop` |
| Merge button | Squash (work PRs, title as the commit message) and merge commits (release PRs); rebase merging disabled |
| Branches | Delete head branches after merge |
| Protection on `main` and `develop` | Require a pull request, require the CI status checks to pass, block force pushes and deletion |
| Security | Enable Dependabot alerts and security updates, secret scanning, and private vulnerability reporting |
| Actions | Allow GitHub-authored and verified actions; workflow permissions read-only by default |

## 7. Releases and versioning

- A release is a pull request from `develop` to `main`, merged with a merge commit.
- Versions follow [Semantic Versioning](https://semver.org/). Tags are created for milestone releases:
  `v1.0.0` for **M1 — Operational Core** and `v2.0.0` for **M2 — Decentralized Trust**. Intermediate
  releases do not need tags.
