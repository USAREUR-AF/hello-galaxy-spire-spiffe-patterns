# Figures

`make-figures.py` draws every figure in this directory from the tree. Nothing in
a figure is typed by hand. Each figure is written in a light and a dark variant
for a `<picture>` element; each SVG holds its own colors and uses system fonts.

```sh
python3 -I docs/figures/make-figures.py           # write the SVG files
python3 -I docs/figures/make-figures.py --check   # exit 1 if a committed file is out of date
```

| Figure | Shows | Data |
|---|---|---|
| `federation` | the two trust domains and the three results of a run: rejected before federation, the public bundle imported, accepted with a mutual TLS handshake | root fingerprints, the openssl error, the handshake result and the SPIRE version from the committed run `docs/sample-report.html` |

The drawing code at the top of `make-figures.py` is shared by the Hello Galaxy
series, so the figures of every repository in it read alike. Text is at least
13 units on an 880-unit canvas. Both variants were rendered in headless Chromium
as an `<img>` at 830 px and 400 px wide and inspected.
