# Running this against a goatnet

The local demo (`bin/hello-spire all`) proves federation self-contained. To run the same
thing **against a goatnet** — a pod's own federated SPIRE identity publishing to and
receiving from the goatnet's Zenoh router over NetBird — there are two sides: a
**one-time operator step** (recognition) and the **partner run** (the pod).

Any appropriate goatnet you have access to works:
EFDI, the shared sandbox goatnet that partners are onboarded to (if you are onboarded to it); <!-- oss-allow: operator-approved public example goatnet -->
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

Recognize the partner pod's trust domain so the goatnet's router accepts its certs. This is
the federation block of goatcore's `spire` role (`ops/ansible/roles/spire`), declared as
config.

1. Get the pod's **public** bundle + trust domain from the partner (the partner runs
   `bin/hello-spire goatnet` once, then `bin/hello-spire goatnet-bundle`).
2. Declare it in the goatnet's `spire` group_vars:
   ```yaml
   spire_federation_enabled: true
   spire_federates_with:
     - trust_domain: "<partner>.pod"
       bundle_endpoint_url: "https://<partner bundle endpoint>"   # for auto-refresh; optional
       endpoint_spiffe_id: "spiffe://<partner>.pod/spire/server"
       bundle_b64: "<base64 of the partner's public bundle>"       # one-time bootstrap
   ```
3. Grant the pod's `POD_CN` write on its namespace in the Zenoh ACL. This is a separate
   authorization step: recognizing a trust domain grants nothing on its own (goatcore
   `docs/design/federated-trust-model.md`).
4. Deploy: `spire-deploy.yml -e target=<site>_hosts`. The role bootstraps the partner
   bundle, folds it into the router trust via `spire-trust-sync`, and restarts the router
   once. Hand the partner the router CA + endpoint for their `goatnet/config.env`.

To stop recognizing a partner: drop the `spire_federates_with` entry and redeploy, or
`spire-server bundle delete -id spiffe://<partner>.pod` (the domain-level kill-switch).

## Partner run (pod side — unprivileged, repeatable)

Prereqs: docker, and this host enrolled as a NetBird peer of the goatnet.

```
cp goatnet/config.env.example goatnet/config.env    # trust domain, router endpoint, POD_CN, CA path
bin/hello-spire goatnet                             # pod SPIRE → X.509-SVID → pub/sub over NetBird
bin/hello-spire goatnet-down                        # tear down
```

Success prints `POD SUB RECEIVED …` — the federated identity sent and received on the
goatnet's router. If it fails: `UnknownIssuer` in `docker logs hs-goatnet-sub` = the
operator has not federated your trust domain yet; silent (no receive) = the ACL grant for
your `POD_CN` is missing.
