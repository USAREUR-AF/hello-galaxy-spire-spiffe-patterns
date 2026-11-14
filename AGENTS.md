# AGENTS.md

Instructions for AI coding agents, and a short version for anyone working here. [CONTRIBUTING.md](CONTRIBUTING.md) is the full process.

## What this repository is

hello-galaxy-spire-spiffe-patterns proves SPIFFE federation: two independent SPIRE trust domains, each with its own root certificate authority, where a workload in one is trusted by the other for mutual TLS only because the two exchanged public trust bundles. It starts two SPIRE servers in Docker Compose and writes an HTML report.

It is one of the Hello Galaxy demonstrations: small, runnable examples, each showing one part of [goat](https://github.com/USAREUR-AF/goatcore). It holds no goat source code.

## Layout

| Path | What |
|---|---|
| `bin/hello-spire` | the runner: `all`, `open`, `down` |
| `lib/` | the proof, the report, and the run against a goatnet |
| `compose/`, `spire/` | the Compose file and the two SPIRE configurations |
| `goatnet/config.env.example` | the values for a run against a goatnet |
| `docs/` | background and a sample report |
| `out/` | written by each run and ignored by git: certificates, private keys, evidence |

## Before you push

CI (`.github/workflows/ci.yml`) runs these. The second block needs Docker and `openssl`.

```bash
for f in bin/hello-spire lib/*.sh; do bash -n "$f"; done
shellcheck -S warning bin/hello-spire lib/*.sh
```

```bash
bin/hello-spire all
grep -qx 'KNOCKOUT=OK' out/results.env
grep -qx 'PROOF=OK' out/results.env
grep -qx 'MTLS=OK' out/results.env
bin/hello-spire down
```

## Rules

1. **Nothing from a real deployment.** No hostname, domain, address, key or person of a real goatnet goes into a file or a commit message. Use made-up names, documentation addresses (RFC 5737) and `example.org` mail.
2. **Commits.** Conventional Commits subject of 100 characters or fewer, with a scope (`fix(<component>): …`). Every commit is signed off (`git commit -s`, the DCO) and signed with a key GitHub verifies. The organization's required check `verified-commits` refuses a pull request that holds an unverified commit.
3. **One logical change per pull request.**
4. **Vulnerabilities** go through [SECURITY.md](SECURITY.md), never a public issue.

The contribution guide for goat as a whole is [goatcore CONTRIBUTING.md](https://github.com/USAREUR-AF/goatcore/blob/main/CONTRIBUTING.md).
