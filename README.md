# hello-galaxy — SPIRE / SPIFFE patterns

A small, self-contained, **runnable proof** that SPIFFE **federation** works: two
independent SPIRE trust domains, each with its own root CA, where a workload in one is trusted by
the other **for real mutual mTLS** — and *only* because they exchanged public trust bundles.

Part of the Hello Galaxy series: small, runnable examples, each showing best practice in one
dimension of [goat](https://github.com/usareur-af/goatcore). One script drives the real thing
end-to-end and the run produces a self-contained **HTML report**. Federation needs two real
certificate authorities, so this demo stands up **two real SPIRE servers** locally in
`docker compose` — nothing mocked.

## What it proves

| # | Claim | How it's shown |
|---|---|---|
| 1 | Two domains, two **independent** CAs | distinct root serials + SHA-256 fingerprints |
| 2 | Each domain issues its **own** workloads | `spire-server x509 mint`, locally, no call to the other |
| 3 | **Knockout** — no cross-domain trust by default | `openssl verify` fails: *unable to get local issuer* |
| 4 | **Federation** imports only the public bundle | `bundle list` shows the peer; fingerprint matches the peer root |
| 5 | After federation, the SVID is **accepted** | `openssl verify` against the federated trust store: OK |
| 6 | A real **mutual cross-domain mTLS** handshake | `openssl s_server -Verify 1` ← `s_client`: *Verify return code: 0 (ok)* |

The knockout is the load-bearing part: cross-domain trust appears **only** after the bundle
exchange. Nothing trusts the other side by default.

## Run it

Needs only **docker** + **openssl**.

```
bin/hello-spire all     # up → federate → prove → render out/report.html  (default)
bin/hello-spire open    # open the report
bin/hello-spire down    # tear down (containers, volumes, evidence)
```

A rendered sample report is committed at [`docs/sample-report.html`](docs/sample-report.html).
The `out/` directory (minted SVIDs + private keys + evidence) is git-ignored and regenerated
each run.

### Run it against a goatnet

The local demo proves the mechanism self-contained. The same pattern runs against a goatnet:
the pod's own federated SPIRE identity publishes to and receives from the goatnet's Zenoh
router over NetBird. This path needs a goatnet you have access to, with SPIRE deployed and
this host enrolled as one of its NetBird peers. That can be
EFDI, the shared sandbox goatnet that partners are onboarded to (if you are onboarded to it); <!-- oss-allow: operator-approved public example goatnet -->
a goatlite you stand up yourself (the goatlite quickstart in
[`goatcore`](https://github.com/usareur-af/goatcore), `docs/tutorials/00-goatlite.md`); or
another goatnet you have access to.

```
cp goatnet/config.env.example goatnet/config.env   # trust domain, router endpoint, POD_CN, router CA
bin/hello-spire goatnet                            # pod SPIRE → X.509-SVID → pub/sub over NetBird
bin/hello-spire goatnet-down                       # tear down
```

It works once the goatnet's operators have stood up an **edge router** for your pod: a
separate router, for your trust domain only, that trusts your SPIRE root and forwards to the
goatnet's core router. A goatnet never adds a partner's root to its core router. Until that
edge exists, the goatnet's core router refuses your pod's identity, which is the correct
result. Both sides are in [`docs/goatnet-onboarding.md`](docs/goatnet-onboarding.md).

## The two domains

- **`core.galaxy`** — stands in for a goatnet SPIRE trust domain (the fabric core).
- **`partner.galaxy`** — stands in for a **partner moon-pod's own** SPIRE trust domain.

Each runs its own SPIRE server = its own root CA. The partner issues and rotates its workloads
**locally**; only the public bundle ever crosses; the partner CA private key never leaves its
domain; each side's SPIRE is a single point of failure for its own domain only.

## How it maps to goat

This is the runnable proof of the partner-pod federation model: a partner runs its **own**
SPIRE and federates, rather than joining the goatnet's trust domain.

- **Design:** goatcore [`docs/design/federated-trust-model.md`](https://github.com/usareur-af/goatcore/blob/main/docs/design/federated-trust-model.md)
  (recognizing a trust domain is separate from authorizing what it may do).
- **Goatnet side:** goatcore `ops/ansible/roles/spire` (`spire_federation_enabled`,
  `spire_federates_with`).
- **Partner side:** [`usareur-af/zagros-moon-pod`](https://github.com/usareur-af/zagros-moon-pod)
  `compose/docker-compose.spire.yml` (the pod overlay — its own server+agent + a
  spiffe-helper sidecar writing a CN-bearing SVID).

## What's real, and what's simplified

**Real:** two SPIRE 1.11.2 servers, two root CAs, real X.509-SVIDs, real `openssl` chain
verification, a real mutual TLS handshake.

**Simplified vs the pod overlay:** leaves are minted with `spire-server x509 mint` (the pod overlay
uses agents + workload attestation + a spiffe-helper sidecar); the federation bootstrap here is a
one-time manual `bundle set` (production adds the auto-refresh `bundle_endpoint`, which is present
in the server confs). These simplifications isolate the *federation* mechanism; they do not change
what is proven.

See [`docs/federation-explained.md`](docs/federation-explained.md) for the concept in depth.

## License

`hello-galaxy-spire-spiffe-patterns` was written by U.S. Federal government employees. In the U.S. it is not subject to copyright and is in the public domain; in countries where copyright is recognized, it is released under the [Apache License 2.0](LICENSE). See [INTENT.md](INTENT.md). See also [NOTICE](NOTICE).
