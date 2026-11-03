# SPIFFE federation, explained

## The three concepts people conflate

| Concept | What it is | What it's for |
|---|---|---|
| **HA** | Multiple SPIRE servers *inside one trust domain*, sharing a datastore + CA key | Remove the single-server SPOF **within** a domain |
| **Federation** | Two *separate* trust domains exchange public trust **bundles** | Let domains **interoperate without sharing a CA** |
| **Membership** | A workload you run the agent for, issued into *your* domain | Just issuance — not cross-domain |

A partner running its own SPIRE is the **federation** case — not HA, not membership. This
demo proves that case.

## Why federation, not "join our SPIRE"

If a partner's workloads were **members** of the goat trust domain (goat's SPIRE issues their
SVIDs), every partner workload's short-TTL rotation would hammer the goat core, and goat would hold
partner identities. Federation avoids both:

- The partner runs its **own** trust domain and issues/rotates its workloads **locally** — the goat
  core mints nothing for them.
- Only the **public bundle** crosses (and only on the CA-TTL cadence). The partner CA **private
  key never leaves the pod**.
- Each side's SPIRE is a SPOF **for its own domain only**. Federation *contains* the SPOF; it does
  not create or remove one. HA (a second server in a domain) is an orthogonal, per-side choice.

## The mechanism this demo exercises

1. **Two roots.** Each SPIRE server is its own CA. By default neither trusts the other — a leaf
   from domain B fails to verify against domain A's root (*unable to get local issuer*).
2. **Bundle exchange.** Each side imports the other's **public** bundle (`bundle set`; production
   refreshes it automatically from the peer's `bundle_endpoint`). After import, `bundle list` on A
   shows B's trust domain and B's exact root fingerprint.
3. **Cross-domain trust.** A leaf from B now verifies against A's *federated* trust store (own root
   + imported B bundle), and a real mutual mTLS handshake completes across the boundary.

The first exchange is bootstrapped out-of-band because neither side trusts the other yet; after
that, the `https_spiffe` bundle endpoint refreshes each bundle on its own.

## How a real pod differs (the `zagros-moon-pod` overlay)

The runnable pod overlay ([`usareur-af/zagros-moon-pod`](https://github.com/usareur-af/zagros-moon-pod) `compose/docker-compose.spire.yml`) adds what
this demo omits for clarity:

- a **SPIRE agent** + **docker workload attestation** (instead of `spire-server x509 mint`),
- a **spiffe-helper** sidecar that writes the Zenoh router a **CN-bearing** SVID so the goat-side
  CN-keyed ACL admits it unchanged (the bridge until an upstream Zenoh URI-SAN matcher lands),
- the reciprocal goat-side `federation` stanza in the `spire` ansible role.

None of those change *what federation proves* — they're the production packaging around the same
mechanism this demo verifies.
