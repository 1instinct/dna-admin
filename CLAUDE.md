# dna-admin

Upstream boilerplate for the DNA platform's admin, CMS and API: Spree 4.2.5 on Rails 6.1 and
Ruby 2.7.2, served to `dna-frontend` and to native apps through the Spree Storefront API and
the platform's own `/api/v1` endpoints. Detailed conventions live in
[.github/copilot-instructions.md](.github/copilot-instructions.md); this file holds the rules
that decide where work goes.

## Where this repo sits

The DNA boilerplates are **dna-admin** (this repo), `1instinct/dna-frontend` (its storefront)
and `1instinct/expo-juce` (a native audio module). Each product forks them into its own
organization and builds its product-specific features there; a fork's own CLAUDE.md names the
product. Forks merge `master` from here to inherit features and fixes, so anything committed
here lands in every fork on its next upstream merge.

## The rule: generalized, product-agnostic features only

A change belongs here only if any product built on DNA would want it as is.

1. No product names, domains, bundle or App Store ids, logos, copy, colours or hardware
   concepts in code, seeds, tests, docs or scripts. Use neutral examples (`example.com`,
   `com.example.app`, `DNA Admin`, `instinct_logo.png`).
1. Anything a product needs to differ is configuration: an env var (`COMPANY_LOGO`,
   `COMPANY_BACKGROUND`, `SITE_TITLE`, ...), an admin-managed record, or a seed with generic
   content that a fork overrides.
1. A feature that is part generic and part product specific is split: the generic core
   (models, API, admin UI) lands here first and reaches the fork through an upstream merge;
   the product layer is built in the fork on top of it.
1. A bug in inherited code is fixed here, then merged down. Fixing it only in a fork makes
   the two drift apart.
1. Deleting or renaming a file here deletes or renames it in every fork on the next merge.
   Say so in the PR when a fork may still depend on it.

## Working here

1. `master` is the trunk; branch from it and open PRs against it.
1. Do not upgrade version-locked dependencies (Ruby, Rails, Spree, Puma); see the copilot
   instructions for the list.
1. `config/initializers/dotenv.rb` requires a set of env vars in development and test; placeholder
   values are enough to run the suite.
1. Seeds in `db/seeds/` run in filename order with a three-digit prefix. Forks number their own
   seeds in the same sequence and may already hold the next number, so a new upstream seed can
   collide with a fork's; the fork renumbers the incoming file on merge.
1. Tests: `bundle exec rails db:test:prepare && DISABLE_SPRING=1 bundle exec rails test`
   (add `OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES` on macOS).

## Commits and PRs

No attribution lines (no `Co-Authored-By`, no generated-by footers). Lists use repeated `1.` so
items can be reordered without renumbering.

```
[Feature|Fix|Chore]: Sentence-case summary of the outcome, changes:
1. What changed, naming the file or symbol, and why
1. Next change
```

PR titles match the commit subject. PR bodies use `## What`, `## Why`, `## Changes` and
`## Verify` sections with `1.` lists, and say which forks are affected when it matters.
