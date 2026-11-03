#!/usr/bin/env bash
# report.sh — render out/steps/* + out/results.env into a rich, self-contained HTML report.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/out"; STEPS="$OUT/steps"; HTML="$OUT/report.html"
[ -f "$OUT/results.env" ] || { echo "no results — run lib/prove.sh all first" >&2; exit 1; }
. "$OUT/results.env"
KO="${KNOCKOUT:-CHECK}"   # results.env writes KNOCKOUT=
TS="$(date -u '+%Y-%m-%d %H:%M:%SZ')"

esc() { sed -e 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' "$1" 2>/dev/null; }
pill() { # $1 = OK|BAD|CHECK -> colored pill
  case "$1" in OK) echo '<span class="pill ok">PASS</span>';;
    BAD) echo '<span class="pill bad">FAIL</span>';; *) echo '<span class="pill warn">CHECK</span>';; esac
}
verdict="ok"; [ "$KO" = OK ] && [ "$PROOF" = OK ] && [ "$MTLS" = OK ] || verdict="warn"

step() { # $1 num, $2 title, $3 file, $4 note
  printf '<section class="step"><div class="sh"><span class="num">%s</span><h3>%s</h3></div>' "$1" "$2"
  [ -n "${4:-}" ] && printf '<p class="note">%s</p>' "$4"
  if [ -f "$STEPS/$3" ]; then printf '<pre>%s</pre>' "$(esc "$STEPS/$3")"; fi
  printf '</section>\n'
}

{
cat <<HTML
<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Hello Galaxy — SPIRE/SPIFFE Federation, Proven</title>
<style>
:root{--bg:#0b0f14;--panel:#11171f;--panel2:#0e141b;--ink:#e7eef6;--dim:#9bb0c2;--faint:#5f7384;
--line:#1e2935;--accent:#38e1c4;--green:#46d68b;--pink:#ff6b8b;--amber:#ffc861;
--mono:ui-monospace,"SF Mono","JetBrains Mono",Menlo,monospace}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);
font:15px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",Inter,sans-serif;
background-image:radial-gradient(1200px 600px at 80% -10%,rgba(56,225,196,.07),transparent)}
.wrap{max-width:980px;margin:0 auto;padding:40px 22px 70px}
.brand{display:flex;align-items:center;gap:12px;color:var(--accent);font-weight:700;letter-spacing:.04em;font-size:13px}
h1{font-size:30px;margin:14px 0 6px;letter-spacing:-.01em}
.sub{color:var(--dim);font-size:15px;margin:0 0 6px;max-width:72ch}
.meta{color:var(--faint);font-size:12px;font-family:var(--mono);margin-top:8px}
.banner{margin:26px 0;padding:18px 20px;border-radius:14px;border:1px solid var(--line);
background:linear-gradient(180deg,rgba(70,214,139,.10),var(--panel));display:flex;align-items:center;gap:14px}
.banner.warn{background:linear-gradient(180deg,rgba(255,200,97,.10),var(--panel))}
.banner .big{font-size:22px;font-weight:800}
.banner .v{margin-left:auto;display:flex;gap:8px;flex-wrap:wrap}
.lede{color:var(--dim);max-width:74ch}
.domains{display:grid;grid-template-columns:1fr 1fr;gap:14px;margin:22px 0}
.dom{border:1px solid var(--line);border-radius:12px;padding:14px 16px;background:var(--panel)}
.dom h4{margin:0 0 6px;font-family:var(--mono);font-size:13px}
.dom .td{color:var(--accent)}.dom small{color:var(--faint);font-family:var(--mono);font-size:11px;word-break:break-all}
.arrow{display:flex;align-items:center;justify-content:center;color:var(--accent);font-size:13px;margin:-6px 0 18px;letter-spacing:.08em}
.step{border:1px solid var(--line);border-radius:12px;padding:16px 18px;margin:14px 0;background:var(--panel)}
.sh{display:flex;align-items:center;gap:12px}.sh h3{margin:0;font-size:16px}
.num{width:26px;height:26px;border-radius:50%;background:var(--panel2);border:1px solid var(--line);
color:var(--accent);font-family:var(--mono);font-weight:700;display:flex;align-items:center;justify-content:center;font-size:13px;flex:none}
.note{color:var(--dim);font-size:13.5px;margin:8px 0 0}
pre{background:var(--panel2);border:1px solid var(--line);border-radius:9px;padding:12px 14px;margin:12px 0 0;
overflow-x:auto;font-family:var(--mono);font-size:12px;color:#cfe0ee;line-height:1.5}
.pill{display:inline-block;font-family:var(--mono);font-size:11px;font-weight:700;letter-spacing:.05em;
padding:2px 9px;border-radius:6px}
.pill.ok{color:var(--green);border:1px solid color-mix(in srgb,var(--green) 55%,transparent)}
.pill.bad{color:var(--pink);border:1px solid color-mix(in srgb,var(--pink) 55%,transparent)}
.pill.warn{color:var(--amber);border:1px solid color-mix(in srgb,var(--amber) 55%,transparent)}
h2{font-size:13px;letter-spacing:.08em;text-transform:uppercase;color:var(--faint);margin:34px 0 6px}
.foot{margin-top:34px;border-top:1px solid var(--line);padding-top:18px;color:var(--dim);font-size:13px}
.foot b{color:var(--ink)} a{color:var(--accent)}
</style></head><body><div class="wrap">
<div class="brand">◇ HELLO GALAXY · SPIRE / SPIFFE PATTERNS</div>
<h1>SPIRE/SPIFFE federation, proven end-to-end</h1>
<p class="sub">Two independent SPIRE trust domains, each its own root CA. Cross-domain trust appears
<b>only</b> after a public-bundle federation exchange — the knockout shows it absent without it.
This is a self-contained, runnable proof of the goat partner-pod federation model.</p>
<div class="meta">run $TS · spire-server 1.11.2 · self-contained docker-compose · no agents, no live fabric</div>

<div class="banner $verdict">
  <span class="big">$([ "$verdict" = ok ] && echo '✓ Federation works' || echo '⚠ Review run')</span>
  <span class="lede">A workload in <code>partner.galaxy</code> is trusted by <code>core.galaxy</code>
  for real mutual mTLS — and only because the bundle was exchanged.</span>
  <span class="v">knockout $(pill "$KO") · chain-verify $(pill "$PROOF") · mTLS $(pill "$MTLS")</span>
</div>

<div class="domains">
  <div class="dom"><h4><span class="td">core.galaxy</span></h4><div>goatnet SPIRE trust domain — its own root CA</div></div>
  <div class="dom"><h4><span class="td">partner.galaxy</span></h4><div>partner moon-pod's OWN SPIRE — its own root CA</div></div>
</div>
<div class="arrow">— federate public bundles only · CA private keys never move —</div>

<h2>The run, step by step</h2>
HTML

step 1 "Two independent SPIRE trust domains come up" 01-up.txt "Each runs its own SPIRE server = its own root CA. They start trusting nothing of each other."
step 2 "Two distinct roots (proof they are separate CAs)" 02-roots.txt "Different serials + fingerprints = genuinely independent certificate authorities."
step 3 "Each domain mints its own leaf SVID locally" 03-mint-pod.txt "spire-server x509 mint — no agent, no call to the other domain. The partner issues its own workloads."
step 4 "KNOCKOUT — before federation, core rejects the pod's SVID" 04-knockout.txt "openssl verify against core's own root only. error 20 = unable to get local issuer: no cross-domain trust exists yet."
step 5 "Federate — exchange PUBLIC bundles only" 05-federate.txt "core imports partner.galaxy's bundle (public keys only; no private key ever moves). The imported fingerprint matches the partner root from step 2."
step 6 "PROOF — core now accepts the pod's SVID" 06-proof.txt "openssl verify against core's post-federation trust store (own root + federated partner bundle): OK."
step 7 "Real mutual cross-domain mTLS handshake" 07-mtls.txt "openssl s_server (core identity, -Verify 1) ← s_client (pod SVID). Verify return code: 0 (ok) = the handshake genuinely completed across the trust-domain boundary."

cat <<HTML
<h2>What this is — and is not</h2>
<div class="foot">
<p><b>Real:</b> two real SPIRE 1.11.2 servers, two real root CAs, real X.509-SVIDs, real
<code>openssl</code> chain verification and a real mutual TLS handshake. Nothing here is mocked.</p>
<p><b>Stands in for:</b> <code>core.galaxy</code> = a goatnet SPIRE trust domain; <code>partner.galaxy</code>
= a partner moon-pod's own SPIRE. It mirrors the goat design decision that
a partner runs its <b>own</b> trust domain and <b>federates</b> — issuing/rotating its workloads
locally, exchanging only public bundles, never loading the goat core with per-cert traffic; each
side's SPIRE is a SPOF for its own domain only.</p>
<p><b>Simplifications vs the pod overlay:</b> leaves are minted with <code>spire-server x509 mint</code>
(the pod overlay uses agents + workload attestation + a spiffe-helper sidecar writing a CN-bearing
SVID); the federation bootstrap here is a one-time manual <code>bundle set</code> (production adds the
auto-refresh <code>bundle_endpoint</code>, which is configured in the server confs). The runnable pod
overlay lives in <code>usareur-af/zagros-moon-pod</code> (<code>compose/docker-compose.spire.yml</code>).</p>
<p>Reproduce: <code>bin/hello-spire all</code> → regenerates this report at <code>out/report.html</code>.</p>
</div>
</div></body></html>
HTML
} > "$HTML"
echo "wrote $HTML"
