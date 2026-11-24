# Operations

Runbook for installing, verifying and recovering the environment.

## Repository tests

```bash
./script/test                       # skips missing linters with a message
REQUIRE_LINTERS=1 ./script/test     # fails instead of skipping; what CI runs
```

Bash 5 or newer is required. Under an older bash the command stops with
`bash 5 or newer is required`.

Install, update and recovery procedures are added as `bootstrap` is built.
