# Running this against a goatnet

The local demo (`bin/hello-spire all`) proves federation self-contained. To run the same
thing **against a goatnet** — a pod's own federated SPIRE identity publishing to and
receiving from the goatnet's Zenoh router over NetBird — there are two sides: a
**one-time operator step** (recognition) and the **partner run** (the pod).

Any appropriate goatnet you have access to works:
a goatlite you stand up yourself (the goatlite quickstart in
[`usareur-af/goatcore`](https://github.com/usareur-af/goatcore), `docs/tutorials/00-goatlite.md`,
or the worked example in
[`usareur-af/hello-galaxy-goatenv`](https://github.com/usareur-af/hello-galaxy-goatenv)); or
another goatnet you have access to. The goatnet needs SPIRE deployed (goatcore
`ops/ansible/spire-deploy.yml`), and the one-time recognition step below needs the goatnet's
operators: you, if you are one, or the operators doing it for you.

The split is deliberate: recognizing a partner is a privileged, infrequent operator action;
running the pod is unprivileged and repeatable. The partner never needs operator access.

## One-time operator step (goatnet side — privileged)

The goatnet recognises the pod's trust domain on an **edge router** of its own, never on its
core router. goatcore's `spire` role writes the core router's trust from the goatnet's own
bundle alone, and refuses to put a partner root there
(`ops/ansible/roles/spire/defaults/main.yml`, the `spire_trust_sync_federated_edges` notes).
The reason is in goatcore `docs/design/federated-trust-model.md`: the router's ACL matches a
certificate's Common Name and cannot see which authority issued it, so a partner root in the
core router could mint any name the core knows.

1. Get the pod's **public** bundle and trust domain from the partner (the partner runs
   `bin/hello-spire goatnet` once, then `bin/hello-spire goatnet-bundle`).
2. Stand up the edge router for that one trust domain with goatcore's federation tooling:
   `goat federate` composes the agreement (the trust domain, the Common Name the pod presents,
   the keys it may write), and `ops/scripts/peering-standup.sh` deploys the edge
   (`ops/ansible/peering-zenoh-edge.yml`, role `ops/ansible/roles/goat-zenoh-edge`). The edge
   trusts your root and the goatnet's, admits exactly the agreed Common Name, and forwards
   only the agreed keys to the core.
3. Hand the partner the edge router's endpoint and CA for their `goatnet/config.env`.

To stop recognising a partner: move its entry to `spire_trust_sync_federated_edges_retired`
and redeploy, or stop the edge container, which cuts the pod's only path at once.

## Partner run (pod side — unprivileged, repeatable)

Prereqs: docker, and this host enrolled as a NetBird peer of the goatnet.

```
cp goatnet/config.env.example goatnet/config.env    # trust domain, router endpoint, POD_CN, CA path
bin/hello-spire goatnet                             # pod SPIRE → X.509-SVID → pub/sub over NetBird
bin/hello-spire goatnet-down                        # tear down
```

Success prints `POD SUB RECEIVED …` — the federated identity sent and received on the
goatnet's router. If it fails with "Unable to connect", you are pointing at a router that does not trust your
root (a goatnet's core router, or an edge that is not yet up); `UnknownIssuer` in
`docker logs hs-goatnet-sub` says the same. Silent (connected, no receive) = the edge's
agreement does not admit your `POD_CN` or your key.
