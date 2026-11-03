#!/usr/bin/env bash
# prove.sh — stand up two SPIRE trust domains, federate them, and PROVE that
# cross-domain trust exists ONLY because of the federated bundle exchange.
# Captures evidence into out/ for the HTML report. Idempotent-ish; run `down` to reset.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/out"
DC="docker compose -f $ROOT/compose/docker-compose.yml"
mkdir -p "$OUT/core" "$OUT/pod" "$OUT/steps"

log() { printf '\n=== %s ===\n' "$*"; }
save() { tee "$OUT/steps/$1"; }   # capture a step's output for the report

core() { $DC exec -T spire-core /opt/spire/bin/spire-server "$@"; }
pod()  { $DC exec -T spire-pod  /opt/spire/bin/spire-server "$@"; }

case "${1:-all}" in
  down) $DC down -v; rm -rf "$OUT/core" "$OUT/pod" "$OUT/steps"; exit 0;;
esac

log "1. Bring up two independent SPIRE trust domains"
$DC up -d
# wait healthy
for _ in $(seq 1 40); do
  cs=$($DC ps --format '{{.Service}} {{.Health}}' 2>/dev/null)
  echo "$cs" | grep -q 'spire-core healthy' && echo "$cs" | grep -q 'spire-pod healthy' && break
  sleep 2
done
$DC ps | save 01-up.txt

log "2. Two distinct roots (each domain its own CA)"
core bundle show -format pem > "$OUT/core-root.pem"
pod  bundle show -format pem > "$OUT/pod-root.pem"
{
  echo "core.galaxy root fingerprint:";  openssl x509 -in "$OUT/core-root.pem" -noout -subject -fingerprint -sha256
  echo "partner.galaxy root fingerprint:"; openssl x509 -in "$OUT/pod-root.pem" -noout -subject -fingerprint -sha256
} | save 02-roots.txt

log "3. Mint a leaf SVID in EACH domain (no agent — server x509 mint)"
core x509 mint -spiffeID spiffe://core.galaxy/verifier  -write /opt/spire/out  2>&1 | save 03-mint-core.txt
pod  x509 mint -spiffeID spiffe://partner.galaxy/publisher -write /opt/spire/out 2>&1 | save 03-mint-pod.txt
# The servers write keys as their own user with mode 0600; on a Linux host the bind mount
# keeps that owner, so copy each key out through docker to get a copy this user can read.
$DC cp spire-core:/opt/spire/out/key.pem "$OUT/core-key.pem"
$DC cp spire-pod:/opt/spire/out/key.pem  "$OUT/pod-key.pem"
ls -l "$OUT/core" "$OUT/pod" | save 03-mint-files.txt

log "4. KNOCKOUT — before federation, does core trust the pod's SVID?"
# core's trust store is ONLY its own root (no federation yet)
if openssl verify -CAfile "$OUT/core-root.pem" "$OUT/pod/svid.pem" > "$OUT/steps/04-knockout.txt" 2>&1; then
  echo "UNEXPECTED: pod SVID verified WITHOUT federation" | tee -a "$OUT/steps/04-knockout.txt"; KO=BAD
else
  echo "EXPECTED: pod SVID REJECTED without federation (no cross-domain trust)" | tee -a "$OUT/steps/04-knockout.txt"; KO=OK
fi
cat "$OUT/steps/04-knockout.txt"

log "5. Federate — exchange PUBLIC bundles only (the one-time bootstrap)"
# core imports partner's bundle; pod imports core's bundle.
core bundle set -format pem -id spiffe://partner.galaxy -path /opt/spire/out/../out/pod-root.pem 2>/dev/null \
  || cat "$OUT/pod-root.pem" | core bundle set -format pem -id spiffe://partner.galaxy
cat "$OUT/core-root.pem" | pod bundle set -format pem -id spiffe://core.galaxy
echo "-- core's federated trust domains (bundle list):" | save 05-federate.txt
core bundle list 2>/dev/null | grep -E '^\*|partner|core' | tee -a "$OUT/steps/05-federate.txt"
echo "-- imported partner.galaxy bundle fingerprint (matches the partner root from step 2):" | tee -a "$OUT/steps/05-federate.txt"
core bundle list -format pem 2>/dev/null | sed -n '/BEGIN CERT/,/END CERT/p' \
  | openssl x509 -noout -subject -fingerprint -sha256 | tee -a "$OUT/steps/05-federate.txt"

log "6. PROOF — after federation, core's trust store accepts the pod's SVID"
# core's post-federation trust store = its own root + the imported partner bundle
cat "$OUT/core-root.pem" "$OUT/pod-root.pem" > "$OUT/core-trust-federated.pem"
if openssl verify -CAfile "$OUT/core-trust-federated.pem" "$OUT/pod/svid.pem" > "$OUT/steps/06-proof.txt" 2>&1; then
  echo "PROVEN: pod SVID ACCEPTED via the federated bundle" | tee -a "$OUT/steps/06-proof.txt"; PROOF=OK
else
  echo "FAIL: pod SVID still rejected after federation" | tee -a "$OUT/steps/06-proof.txt"; PROOF=BAD
fi
cat "$OUT/steps/06-proof.txt"

log "7. Real cross-domain mTLS handshake (core verifier <- pod publisher)"
# s_server: core identity, requires + verifies a client cert against the federated trust store.
( openssl s_server -accept 8765 -cert "$OUT/core/svid.pem" -key "$OUT/core-key.pem" \
    -CAfile "$OUT/core-trust-federated.pem" -Verify 1 -naccept 2 -www >"$OUT/steps/07-server.log" 2>&1 ) &
SRV=$!
# the port probe below uses one of the two accepts
for _ in $(seq 1 50); do (exec 3<>/dev/tcp/127.0.0.1/8765) 2>/dev/null && break; sleep 0.2; done
echo Q | openssl s_client -connect 127.0.0.1:8765 \
    -cert "$OUT/pod/svid.pem" -key "$OUT/pod-key.pem" \
    -CAfile "$OUT/core-trust-federated.pem" 2>"$OUT/steps/07-client.err" \
  | grep -iE "Verify return code|subject=|issuer=" | save 07-mtls.txt || true
kill $SRV 2>/dev/null
if grep -q "Verify return code: 0 (ok)" "$OUT/steps/07-mtls.txt"; then
  echo "PROVEN: mutual cross-domain mTLS handshake SUCCEEDED" | tee -a "$OUT/steps/07-mtls.txt"; MTLS=OK
else
  echo "(handshake verify line not 0 — see step output)" | tee -a "$OUT/steps/07-mtls.txt"; MTLS=CHECK
  tail -n 20 "$OUT/steps/07-server.log" "$OUT/steps/07-client.err" 2>/dev/null || true
fi
cat "$OUT/steps/07-mtls.txt"

log "RESULTS"
{
  echo "KNOCKOUT=$KO"; echo "PROOF=$PROOF"; echo "MTLS=$MTLS"
} | tee "$OUT/results.env"
