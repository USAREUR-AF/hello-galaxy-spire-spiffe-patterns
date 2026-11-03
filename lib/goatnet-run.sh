#!/usr/bin/env bash
# goatnet-run.sh — PARTNER (pod) side, against a goatnet you have access to.
#
# Stands up the pod's OWN SPIRE trust domain, mints a CN-bearing X.509-SVID, and
# publishes + subscribes to the goatnet's Zenoh router over the NetBird mesh —
# one federated identity, both directions. Needs docker and this host being a
# NetBird peer of the goatnet. The goatnet must already trust this pod (operator
# one-time step; see docs/goatnet-onboarding.md) — otherwise the mTLS handshake
# is refused (UnknownIssuer).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CFG="$ROOT/goatnet/config.env"
[ -f "$CFG" ] || { echo "missing $CFG — copy goatnet/config.env.example and fill it in" >&2; exit 1; }
# shellcheck disable=SC1090
. "$CFG"
: "${POD_TRUST_DOMAIN:?}"; : "${ROUTER_ENDPOINT:?}"; : "${POD_CN:?}"; : "${ROUTER_CA:?}"; : "${POD_KEY:?}"
TD="${POD_TRUST_DOMAIN#spiffe://}"
CA="$ROOT/$ROUTER_CA"; [ -f "$CA" ] || CA="$ROUTER_CA"
[ -f "$CA" ] || { echo "router CA not found: $ROUTER_CA" >&2; exit 1; }
D="$ROOT/out/goatnet"; C="$D/certs"; mkdir -p "$C"
SIMG="ghcr.io/spiffe/spire-server:1.11.2"
PYIMG="hello-spire-goatnet-py"
leaf(){ awk '/BEGIN CERTIFICATE/{c++} c==1{print} /END CERTIFICATE/&&c==1{exit}'; }
key(){ awk '/BEGIN.*PRIVATE KEY/{k=1} k{print} /END.*PRIVATE KEY/{exit}'; }
log(){ printf '\n=== %s ===\n' "$*"; }

case "${1:-run}" in
  down)
    docker rm -f hs-goatnet-pod-spire hs-goatnet-sub >/dev/null 2>&1 || true
    docker rmi "$PYIMG" >/dev/null 2>&1 || true
    rm -rf "$D"; echo "torn down"; exit 0 ;;
  bundle)
    # print this pod's PUBLIC bundle, for the operator to federate (one-time).
    docker exec hs-goatnet-pod-spire /opt/spire/bin/spire-server bundle show -format pem 2>/dev/null \
      || echo "pod SPIRE not up yet — run 'bin/hello-spire goatnet' first" ; exit 0 ;;
esac

log "1. Stand up the pod's OWN SPIRE trust domain ($POD_TRUST_DOMAIN)"
cat > "$D/server.conf" <<CONF
server { bind_address="0.0.0.0" bind_port="8081" trust_domain="$TD" data_dir="/opt/spire/data" log_level="INFO" ca_ttl="24h" default_x509_svid_ttl="1h" }
plugins { DataStore "sql" { plugin_data { database_type="sqlite3" connection_string="/opt/spire/data/datastore.sqlite3" } } KeyManager "disk" { plugin_data { keys_path="/opt/spire/data/keys.json" } } NodeAttestor "join_token" { plugin_data {} } }
health_checks { listener_enabled=true bind_address="0.0.0.0" bind_port="8080" }
CONF
docker rm -f hs-goatnet-pod-spire >/dev/null 2>&1 || true
docker run -d --name hs-goatnet-pod-spire --user 0:0 \
  -v "$D/server.conf":/run/spire/server.conf:ro -v "$D/pod-data":/opt/spire/data \
  "$SIMG" -config /run/spire/server.conf >/dev/null
for _ in $(seq 1 20); do docker exec hs-goatnet-pod-spire /opt/spire/bin/spire-server healthcheck >/dev/null 2>&1 && break; sleep 1; done
echo "pod SPIRE: $(docker exec hs-goatnet-pod-spire /opt/spire/bin/spire-server healthcheck 2>&1 | tail -1)"

log "2. Mint the pod's CN-bearing X.509-SVID (CN=$POD_CN)"
out="$(docker exec hs-goatnet-pod-spire /opt/spire/bin/spire-server x509 mint -spiffeID "spiffe://$TD/fed-app" -dns "$POD_CN" 2>/dev/null)"
echo "$out" | leaf > "$C/svid.pem"; echo "$out" | key > "$C/key.pem"
cp "$CA" "$C/router-ca.pem"
echo "minted: $(openssl x509 -in "$C/svid.pem" -noout -subject 2>&1)"

log "3. Build the zenoh python client (one-time)"
printf 'FROM python:3.12-slim\nRUN pip install --no-cache-dir eclipse-zenoh==1.9.0\n' > "$D/Dockerfile.py"
docker build -q -t "$PYIMG" -f "$D/Dockerfile.py" "$D" >/dev/null 2>&1 && echo "image ok"
cat > "$D/conf.json5" <<EOF
{ mode:"client", connect:{endpoints:["$ROUTER_ENDPOINT"]}, transport:{link:{tls:{ root_ca_certificate:"/certs/router-ca.pem", connect_certificate:"/certs/svid.pem", connect_private_key:"/certs/key.pem", enable_mtls:true }}}}
EOF
cat > "$D/sub.py" <<EOF
import zenoh,time
s=zenoh.open(zenoh.Config.from_file("/cfg/conf.json5")); g=[]
def cb(x):
    try:d=bytes(x.payload)
    except:d=x.payload.to_bytes()
    g.append(d); print("POD SUB RECEIVED",str(x.key_expr),d.decode(errors="replace"),flush=True)
s.declare_subscriber("${POD_KEY%/*}/**",cb); print("POD SUBSCRIBED (over NetBird, federated X509-SVID)",flush=True)
time.sleep(16); print("COUNT",len(g),flush=True)
EOF
cat > "$D/pub.py" <<EOF
import zenoh,time
s=zenoh.open(zenoh.Config.from_file("/cfg/conf.json5")); time.sleep(2)
s.put("$POD_KEY", b"pod -> NetBird -> goatnet zenoh, via federated SPIRE X509-SVID"); print("POD PUBLISHED (over NetBird)",flush=True); time.sleep(2); s.close()
EOF

log "4. Round trip over NetBird (federated identity both directions)"
docker rm -f hs-goatnet-sub >/dev/null 2>&1 || true
docker run -d --name hs-goatnet-sub --network host -v "$C":/certs:ro -v "$D/conf.json5":/cfg/conf.json5:ro -v "$D/sub.py":/cfg/sub.py:ro "$PYIMG" python /cfg/sub.py >/dev/null
sleep 7
docker logs hs-goatnet-sub 2>&1 | grep -iE "SUBSCRIBED|ZError|error" | head -2
docker run --rm --network host -v "$C":/certs:ro -v "$D/conf.json5":/cfg/conf.json5:ro -v "$D/pub.py":/cfg/pub.py:ro "$PYIMG" python /cfg/pub.py 2>&1 | grep -iE "PUBLISHED|ZError" | head -2
sleep 4

log "RESULT"
if docker logs hs-goatnet-sub 2>&1 | grep -q "POD SUB RECEIVED"; then
  docker logs hs-goatnet-sub 2>&1 | grep -iE "RECEIVED|COUNT" | head
  echo "✓ PROVEN: federated identity sent AND received on the goatnet over NetBird"
else
  echo "✗ no data received. Most likely the goatnet side does not yet trust this pod —"
  echo "  the operator must federate '$POD_TRUST_DOMAIN' + grant CN=$POD_CN (docs/goatnet-onboarding.md)."
  echo "  Check: docker logs hs-goatnet-sub  (UnknownIssuer = federation missing; silent = ACL missing)."
fi
echo "(teardown: bin/hello-spire goatnet-down)"
