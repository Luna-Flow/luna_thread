#let acm-paper(
  title: none,
  subtitle: none,
  authors: (),
  affiliation: none,
  email: none,
  abstract: none,
  keywords: (),
  body,
  text-font: "Libertinus Serif",
  title-font: "Helvetica",
  code-font: "Menlo",
  lang: "en",
) = {
  set page(
    paper: "us-letter",
    margin: (
      top: 0.85in,
      bottom: 1.0in,
      inside: 0.78in,
      outside: 0.78in,
    ),
  )
  set text(font: text-font, size: 9pt, lang: lang)
  set par(justify: true, leading: 0.48em)
  set heading(numbering: "1.")

  show heading.where(level: 1): it => [
    #v(0.9em)
    #text(font: title-font, size: 11pt, weight: "bold")[#it.body]
    #v(0.25em)
  ]

  show heading.where(level: 2): it => [
    #v(0.65em)
    #text(font: title-font, size: 9.6pt, weight: "bold")[#it.body]
    #v(0.15em)
  ]

  show heading.where(level: 3): it => [
    #v(0.45em)
    #text(font: title-font, size: 9pt, weight: "semibold")[#it.body]
    #v(0.1em)
  ]

  show raw: set text(font: code-font, size: 8pt)

  [
    #align(center)[
      #text(font: title-font, size: 18pt, weight: "bold")[#title]
      #if subtitle != none [
        #v(0.35em)
        #text(font: title-font, size: 9pt, fill: rgb("#4d4d4d"))[#subtitle]
      ]
      #v(0.8em)
      #text(font: title-font, size: 10pt, weight: "semibold")[#authors]
      #if affiliation != none [
        #linebreak()
        #text(size: 8.5pt)[#affiliation]
      ]
      #if email != none [
        #linebreak()
        #text(size: 8.5pt)[#email]
      ]
    ]

    #v(0.9em)
    #text(font: title-font, size: 10pt, weight: "bold")[
      #if lang == "zh" [摘要] else [ABSTRACT]
    ]
    #v(0.2em)
    #abstract

    #v(0.55em)
    #text(font: title-font, size: 9pt, weight: "bold")[
      #if lang == "zh" [关键词] else [Keywords]
    ]:
    #keywords

    #v(0.8em)
    #set page(columns: 2)
    #body
  ]
}

#let estimate-table(headers, rows) = table(
  columns: (1.8fr, 1.2fr, 2.8fr),
  inset: 6pt,
  stroke: 0.4pt + luma(190),
  table.header(
    ..headers,
  ),
  ..rows,
)

#let compact-note(body) = block(
  inset: 7pt,
  fill: luma(246),
  stroke: (paint: luma(210), thickness: 0.4pt),
  radius: 2pt,
  body,
)

#let diagram-box(label, width: auto) = block(
  width: width,
  inset: (x: 8pt, y: 6pt),
  fill: luma(248),
  stroke: (paint: rgb("#94a3b8"), thickness: 0.5pt),
  radius: 2pt,
  align(center)[#label],
)

#let diagram-panel(title, body) = block(
  width: 100%,
  inset: 8pt,
  fill: luma(250),
  stroke: (paint: rgb("#cbd5e1"), thickness: 0.5pt),
  radius: 3pt,
  [
    #align(center)[#text(weight: "bold")[#title]]
    #v(0.35em)
    #body
  ],
)

#let down-arrow() = align(center)[#text(fill: rgb("#64748b"), size: 11pt)[↓]]

#let split-arrows(left: "↓", right: "↓") = grid(
  columns: (1fr, 1fr),
  gutter: 10pt,
  align(center)[#text(fill: rgb("#64748b"), size: 11pt)[#left]],
  align(center)[#text(fill: rgb("#64748b"), size: 11pt)[#right]],
)
