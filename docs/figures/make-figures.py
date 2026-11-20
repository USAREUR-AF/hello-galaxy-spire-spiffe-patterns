"""Draw the repository's figures from the tree.

    python3 -I docs/figures/make-figures.py           # write docs/figures/*.svg
    python3 -I docs/figures/make-figures.py --check   # exit 1 if a committed figure is out of date

Each figure is written twice, `<name>-light.svg` and `<name>-dark.svg`, for a
`<picture>` element. The root fingerprints, the knockout error and the
handshake result in `federation` are read from the committed run,
docs/sample-report.html; the script refuses to draw if one is missing.
Regenerate after the sample report is replaced. Standard library only.
"""

# ---- Hello Galaxy figure kit (shared by the series; standard library only) ----
# One visual language for every Hello Galaxy figure: the token palette, type
# sizes, boxes, stage dots and arrows below. Each figure is written twice,
# <name>-light.svg and <name>-dark.svg, for a <picture> element; each file is
# self-contained (its colors are declared inside it; no remote font).

import os
import sys
from xml.sax.saxutils import escape

THEMES = {
    "light": "--ink:#191c22; --quiet:#555c68; --rule:#dde1e6; --line:#878f9c; --paper:#ffffff; "
             "--panel:#f5f6f8; --accent:#0b5a72; --accent-soft:#e2f0f4; --on-accent:#ffffff; "
             "--good:#2a6a35; --good-bg:#e4f3e6; --warn:#875200; --warn-bg:#fcf0d7; --info:#285d9e; "
             "--info-bg:#e6eff9; --crit:#b0261d; --crit-bg:#fbeae8; --mute:#5a606a; --mute-bg:#efeeeb;",
    "dark": "--ink:#e7e9ec; --quiet:#a5acb7; --rule:#30363e; --line:#7b8592; --paper:#121417; "
            "--panel:#1a1d21; --accent:#6cc3da; --accent-soft:#14303a; --on-accent:#121417; "
            "--good:#6fc480; --good-bg:#1b2e20; --warn:#e2b04e; --warn-bg:#32291a; --info:#86b3ea; "
            "--info-bg:#1a2636; --crit:#f08b80; --crit-bg:#3a1f1f; --mute:#9ba2ac; --mute-bg:#24262b;",
}
SANS = "'Helvetica Neue',Helvetica,Arial,'Liberation Sans',sans-serif"
MONO = "Menlo,Consolas,'Liberation Mono',monospace"
CLASSES = """
.t{fill:var(--ink)} .tq{fill:var(--quiet)} .ta{fill:var(--accent)} .tg{fill:var(--good)}
.tw{fill:var(--warn)} .ti{fill:var(--info)} .tc{fill:var(--crit)} .tm{fill:var(--mute)} .ton{fill:var(--on-accent)}
.bx{fill:var(--paper);stroke:var(--line);stroke-width:1.25} .bxp{fill:var(--panel);stroke:var(--rule);stroke-width:1.25}
.bxa{fill:var(--accent-soft);stroke:var(--accent);stroke-width:1.25} .bxg{fill:var(--good-bg);stroke:var(--good);stroke-width:1.25}
.bxw{fill:var(--warn-bg);stroke:var(--warn);stroke-width:1.25} .bxi{fill:var(--info-bg);stroke:var(--info);stroke-width:1.25}
.bxc{fill:var(--crit-bg);stroke:var(--crit);stroke-width:1.25} .bxm{fill:var(--mute-bg);stroke:var(--mute);stroke-width:1.25}
.bxd{fill:var(--paper);stroke:var(--line);stroke-width:1.25;stroke-dasharray:5 4}
.bxz{fill:none;stroke:var(--accent);stroke-width:1.25;stroke-dasharray:6 4}
.ln{stroke:var(--line);stroke-width:1.5;fill:none} .lna{stroke:var(--accent);stroke-width:2.25;fill:none}
.lng{stroke:var(--good);stroke-width:2;fill:none} .lnw{stroke:var(--warn);stroke-width:2;fill:none}
.lnc{stroke:var(--crit);stroke-width:2;fill:none} .lnx{stroke:var(--crit);stroke-width:2;fill:none;stroke-dasharray:4 5}
.lnd{stroke:var(--line);stroke-width:1.25;fill:none;stroke-dasharray:6 5} .lnr{stroke:var(--rule);stroke-width:1;fill:none}
.fa{fill:var(--accent)} .fg{fill:var(--good)} .fl{fill:var(--line)} .fw{fill:var(--warn)} .fi{fill:var(--info)}
.fc{fill:var(--crit)} .fm{fill:var(--mute)} .fp{fill:var(--panel)} .fs{fill:var(--accent-soft)} .fpaper{fill:var(--paper)}
.mono{font-family:%s}
""" % MONO
HEAD = {"ln": "fl", "lna": "fa", "lng": "fg", "lnw": "fw", "lnc": "fc", "lnx": "fc", "lnd": "fl"}

TITLE = 20      # the finding, top left
LABEL = 15      # a box's name
SUB = 15        # the line under the title
BODY = 14       # everything else; never smaller


def n(v):
    return ("%.1f" % v).rstrip("0").rstrip(".")


def tw(s, size, mono=False, bold=False):
    """Text width estimate for a system sans; generous on purpose."""
    if mono:
        return len(s) * size * 0.62
    w = 0.0
    for c in s:
        if c in "il.,:;|!'`·1 ":
            w += 0.30
        elif c in "ft()[]/-":
            w += 0.37
        elif c in "mwMW@%":
            w += 0.88
        elif c.isupper() or c in "0123456789≤≥→←":
            w += 0.66
        else:
            w += 0.56
    return w * size * (1.07 if bold else 1.0)


def wrap(s, width, size, mono=False, bold=False):
    out, line = [], ""
    for word in s.split(" "):
        t = word if not line else line + " " + word
        if tw(t, size, mono, bold) <= width or not line:
            line = t
        else:
            out.append(line)
            line = word
    if line:
        out.append(line)
    return out


class Fig:
    def __init__(self, w, h, title, alt):
        self.w, self.h, self.alt, self.parts = w, h, alt, []
        self.text(24, 38, title, TITLE, bold=True, role="title")

    def add(self, s):
        self.parts.append(s)

    def text(self, x, y, s, size=BODY, cls="t", anchor="start", bold=False, mono=False, role=None):
        if not mono and size < 13:
            raise SystemExit("text under 13 units: %r" % s)
        a = ' text-anchor="%s"' % anchor if anchor != "start" else ""
        b = ' font-weight="700"' if bold else ""
        r = ' data-role="%s"' % role if role else ""
        c = cls + (" mono" if mono else "")
        self.add('<text x="%s" y="%s" class="%s" font-size="%s"%s%s%s>%s</text>'
                 % (n(x), n(y), c, n(size), a, b, r, escape(s)))

    def sub(self, s):
        """The line under the title."""
        if tw(s, SUB) > self.w - 48:
            raise SystemExit("subtitle too long: %r" % s)
        self.text(24, 66, s, SUB, "tq")

    def lines(self, x, y, rows, size=BODY, lead=1.45, **kw):
        for i, r in enumerate(rows):
            self.text(x, y + i * size * lead, r, size, **kw)
        return y + len(rows) * size * lead

    def rect(self, x, y, w, h, cls="bx", rx=8):
        self.add('<rect x="%s" y="%s" width="%s" height="%s" rx="%s" class="%s"/>'
                 % (n(x), n(y), n(w), n(h), n(rx), cls))

    def box(self, x, y, w, h, cls, name, rows=(), name_cls="t", mono_rows=False, pad=14, center=False):
        """A box with a bold name and quiet rows under it."""
        self.rect(x, y, w, h, cls)
        cx = x + w / 2 if center else x + pad
        anc = "middle" if center else "start"
        self.text(cx, y + pad + LABEL * 0.8, name, LABEL, name_cls, anc, bold=True)
        yy = y + pad + LABEL * 0.8 + BODY * 1.5
        for r in rows:
            self.text(cx, yy, r, BODY, "tq", anc, mono=mono_rows)
            yy += BODY * 1.45

    def circle(self, x, y, r, cls):
        self.add('<circle cx="%s" cy="%s" r="%s" class="%s"/>' % (n(x), n(y), n(r), cls))

    def dot(self, x, y, label, cls="fa"):
        """A numbered stage dot, as in every Hello Galaxy figure."""
        self.circle(x, y, 15, cls)
        self.text(x, y + 4.6, str(label), 13, "ton", "middle", bold=True)

    def path(self, d, cls="ln"):
        self.add('<path d="%s" class="%s"/>' % (d, cls))

    def arrow(self, pts, cls="ln", head=True, size=10):
        """A polyline through pts, with a filled head at the last point."""
        (x1, y1), (x2, y2) = pts[-2], pts[-1]
        if head:
            dx, dy = x2 - x1, y2 - y1
            L = (dx * dx + dy * dy) ** 0.5 or 1
            ux, uy = dx / L, dy / L
            bx, by = x2 - ux * size, y2 - uy * size
            pts = pts[:-1] + [(bx + ux, by + uy)]
            px, py = -uy * size * 0.5, ux * size * 0.5  # 10 long by 10 wide
            self.add('<path d="M%s %sL%s %sL%s %sz" class="%s"/>'
                     % (n(x2), n(y2), n(bx + px), n(by + py), n(bx - px), n(by - py), HEAD.get(cls, "fl")))
        d = "M" + "L".join("%s %s" % (n(x), n(y)) for x, y in pts)
        self.path(d, cls)

    def tick(self, x, y, cls="fg"):
        """A filled check mark disc."""
        self.circle(x, y, 10, cls)
        self.add('<path d="M%s %sl3.6 3.6l6.4-7.2" style="stroke:var(--paper);stroke-width:2.4;fill:none;'
                 'stroke-linecap:round;stroke-linejoin:round"/>' % (n(x - 5), n(y)))

    def cross(self, x, y, cls="fc"):
        """A filled cross disc."""
        self.circle(x, y, 10, cls)
        self.add('<path d="M%s %sl8 8M%s %sl-8 8" style="stroke:var(--paper);stroke-width:2.4;'
                 'stroke-linecap:round"/>' % (n(x - 4), n(y - 4), n(x + 4), n(y - 4)))

    def render(self, theme):
        style = "svg{%s font-family:%s}%s" % (THEMES[theme], SANS, CLASSES)
        return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %s %s" width="%s" height="%s" '
                'role="img" aria-label="%s"><style>%s</style>\n%s\n</svg>\n'
                % (n(self.w), n(self.h), n(self.w), n(self.h), escape(self.alt, {'"': "&quot;"}),
                   style, "\n".join(self.parts)))


def write_all(figures, here, argv):
    """figures: {name: Fig}. Write <name>-light/-dark.svg, or with --check report drift."""
    check = "--check" in argv
    stale = []
    for name, fig in figures.items():
        for theme in ("light", "dark"):
            path = os.path.join(here, "%s-%s.svg" % (name, theme))
            body = fig.render(theme)
            if check:
                try:
                    with open(path, encoding="utf-8") as f:
                        if f.read() != body:
                            stale.append(path)
                except FileNotFoundError:
                    stale.append(path)
            else:
                with open(path, "w", encoding="utf-8") as f:
                    f.write(body)
                print("wrote", os.path.relpath(path, os.path.dirname(os.path.dirname(here))))
    if check:
        for p in stale:
            print("out of date:", p, file=sys.stderr)
        if stale:
            print("run: python3 -I docs/figures/make-figures.py", file=sys.stderr)
            return 1
        print("figures up to date")
    return 0
# ---- end of the Hello Galaxy figure kit ----


import html
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))


def report():
    with open(os.path.join(ROOT, "docs", "sample-report.html"), encoding="utf-8") as h:
        t = html.unescape(re.sub(r"<[^>]+>", "", h.read()))
    fp = dict((m.group(1), m.group(2)) for m in re.finditer(
        r"(core|partner)\.galaxy root fingerprint:\s*subject=[^\n]*\n\s*sha256 Fingerprint=([0-9A-F:]+)", t))
    knock = re.search(r"error 20 at 0 depth lookup: (unable to get local issuer certificate)", t)
    ok = re.search(r"Verify return code: 0 \(ok\)", t)
    accepted = re.search(r"PROVEN: pod SVID ACCEPTED via the federated bundle", t)
    if set(fp) != {"core", "partner"} or not (knock and ok and accepted):
        raise SystemExit("federation: docs/sample-report.html no longer shows the run this figure draws")
    ver = re.search(r"spire-server:([0-9.]+)@sha256", t)
    if not ver:
        raise SystemExit("federation: the SPIRE version is no longer in docs/sample-report.html")
    return {"core": fp["core"], "partner": fp["partner"], "knock": knock.group(1), "ver": ver.group(1)}


def short(fp):
    return ":".join(fp.split(":")[:4]) + "…"


def fig_federation():
    R = report()
    f = Fig(880, 460, "A partner workload is trusted only after its public bundle is imported",
            "Two SPIRE servers, core.galaxy and partner.galaxy, each with its own root CA "
            "(fingerprints %s and %s). Before federation, core rejects the partner workload's "
            "certificate: %s. After core imports partner.galaxy's public bundle, the certificate "
            "verifies and a mutual TLS handshake completes with verify return code 0 (ok)."
            % (short(R["core"]), short(R["partner"]), R["knock"]))
    f.sub("From the committed run, docs/sample-report.html: two SPIRE servers in "
                   "docker compose, checked with openssl.")
    SW, Y0, Y1 = 196, 98, 440
    # the two trust domains
    for x, name, role, fp in ((20, "core.galaxy", ["stands in for a", "goatnet trust domain"], R["core"]),
                              (880 - 20 - SW, "partner.galaxy", ["stands in for a", "partner pod's SPIRE"],
                               R["partner"])):
        f.rect(x, Y0, SW, Y1 - Y0, "bxp", rx=12)
        f.text(x + 16, Y0 + 30, name, LABEL, "t", bold=True, mono=True)
        f.lines(x + 16, Y0 + 56, role, BODY, cls="tq")
        f.rect(x + 16, Y0 + 104, SW - 32, 66, "bx")
        f.text(x + 30, Y0 + 130, "own root CA", BODY, "t", bold=True)
        f.text(x + 30, Y0 + 152, short(fp), 13, "tq", mono=True)
        f.text(x + 16, Y0 + 204, "issues its own", BODY, "tq")
        f.text(x + 16, Y0 + 224, "workloads locally", BODY, "tq")
        f.text(x + 16, Y1 - 24, "SPIRE server " + R["ver"], BODY, "tq")
    # three lanes between them, partner on the right, core on the left
    LX0, LX1 = 20 + SW + 18, 880 - 20 - SW - 18
    lanes = [
        (1, "Before: core rejects the partner's SVID", "lnx", "cross", "openssl verify: " + "unable to get",
         "local issuer certificate", "tc"),
        (2, "Federate: core imports the public bundle", "lna", None, "only public keys; no private key moves;",
         "fingerprint matches %s" % short(R["partner"]), "tq"),
        (3, "After: the SVID is accepted", "lng", "tick", "and a mutual TLS handshake completes:",
         "Verify return code: 0 (ok)", "tg"),
    ]
    for i, (num, head, cls, mark, d1, d2, dcls) in enumerate(lanes):
        y = Y0 + 16 + i * 114
        f.dot(LX0 + 13, y + 6, num)
        f.text(LX0 + 36, y + 11, head, BODY, "t", bold=True)
        ay = y + 38
        if num == 3:
            mid = (LX0 + LX1) / 2
            f.arrow([(mid, ay), (LX1, ay)], cls)
            f.arrow([(mid, ay), (LX0, ay)], cls)
        elif mark == "cross":
            f.arrow([(LX1, ay), (LX0 + 30, ay)], cls, head=False)
        else:
            f.arrow([(LX1, ay), (LX0, ay)], cls)
        if mark == "cross":
            f.cross(LX0 + 18, ay)
        elif mark == "tick":
            f.tick((LX0 + LX1) / 2, ay)
        f.text(LX0 + 36, ay + 26, d1, BODY, dcls if num != 2 else "tq", mono=False)
        f.text(LX0 + 36, ay + 45, d2, BODY, dcls, mono=(num == 3))
    return f


def main(argv):
    return write_all({"federation": fig_federation()}, HERE, argv)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
