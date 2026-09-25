# AGENTS.md

## Operating defaults

- Keep changes KISS and preserve unrelated work.
- Testing: default to **zero new tests**. Use the smallest existing validation that can prove the change. Add or modify tests only for a real uncovered regression, contract, security boundary, failure mode, or high-signal isolated logic. Once required checks pass and the changed behavior is proven, **stop**.
- Runners: this is a public repository; normal GitHub Actions should use `ubuntu-latest` unless a repository-specific requirement proves otherwise. Do not create a second CI architecture without a real need.
- When available on Amit's machines, follow `~/.agent/CORE.md` and `~/.agent/TESTING.md`; repository-specific authority still takes precedence.
