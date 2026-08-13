// Tema APIGLM equivalente al tema CSS de documentacion.

#let ink = rgb("#1f2937")
#let heading-color = rgb("#123b5d")
#let heading-soft = rgb("#1f5f88")
#let accent = rgb("#0b8fa3")
#let accent-soft = rgb("#e6f5f7")
#let table-header = rgb("#f8fafc")
#let table-row-alt = rgb("#fbfdfe")
#let line = rgb("#c9d7e3")
#let code-surface = rgb("#f3f6f8")
#let code-ink = rgb("#243746")

#set page(
  paper: "a4",
  margin: (top: 17mm, right: 15mm, bottom: 18mm, left: 15mm),
)
#set text(
  font: ("Poppins", "Segoe UI", "Arial"),
  size: 10.5pt,
  fill: ink,
)
#set par(
  leading: 0.65em,
  spacing: 9pt,
)
#set block(spacing: 9pt)
#set table(
  align: (x, y) => left,
  stroke: 0.5pt + line,
  inset: (x: 10pt, y: 7pt),
  fill: (x, y) => if y == 0 {
    table-header
  } else if calc.rem(y, 2) == 0 {
    table-row-alt
  } else {
    none
  },
)

#show link: set text(fill: rgb("#056b9a"))

#show figure.where(kind: table): it => it.body

#show table.cell: set text(
  font: ("Poppins", "Segoe UI", "Arial"),
  size: 9.3pt,
  fill: ink,
)

#show table.cell.where(y: 0): set text(
  size: 9.1pt,
  weight: "semibold",
  fill: rgb("#475569"),
)

#show heading.where(level: 1): it => block(
  width: 100%,
  below: 18pt,
  inset: (bottom: 10pt),
  stroke: (bottom: 3pt + accent),
)[
  #set text(size: 24pt, weight: "semibold", fill: heading-color)
  #it.body
]

#show heading.where(level: 2): it => block(
  width: 100%,
  above: 13pt,
  below: 9pt,
  inset: (left: 10pt, top: 5pt, bottom: 5pt),
  stroke: (left: 4pt + accent),
)[
  #set text(size: 15pt, weight: "semibold", fill: rgb("#334155"))
  #it.body
]

#show heading.where(level: 3): it => {
  set text(size: 12.5pt, weight: "semibold", fill: heading-soft)
  it
}

#show heading.where(level: 4): it => {
  set text(size: 11pt, weight: "semibold", fill: heading-soft)
  it
}

#show raw.where(block: true): it => block(
  width: 100%,
  above: 9pt,
  below: 12pt,
  inset: 10pt,
  fill: code-surface,
  stroke: (left: 4pt + accent, rest: 0.5pt + line),
  radius: 3pt,
)[
  #set text(font: "Consolas", size: 8.5pt, fill: code-ink)
  #it.text
]

$body$
