#let jmlr-paper(
  title: none,
  subtitle: none,
  authors: (),
  affiliation: none,
  email: none,
  abstract: none,
  keywords: (),
  body,
  text-font: "Times New Roman",
  title-font: "Times New Roman",
  code-font: "Menlo",
  lang: "en",
) = {
  set page(
    paper: "us-letter",
    margin: (x: 1.25in, top: 1in, bottom: 1in),
    numbering: "1",
  )
  set text(font: text-font, size: 11pt, lang: lang)
  set par(justify: true, leading: 0.42em)
  set heading(numbering: "1.")

  show heading.where(level: 1): it => [
    #v(0.8em)
    #text(font: title-font, size: 12pt, weight: "bold")[#it.body]
    #v(0.18em)
  ]

  show heading.where(level: 2): it => [
    #v(0.55em)
    #text(font: title-font, size: 11pt, weight: "bold")[#it.body]
    #v(0.08em)
  ]

  show heading.where(level: 3): it => [
    #v(0.35em)
    #text(font: title-font, size: 11pt, weight: "semibold")[#it.body]
    #v(0.06em)
  ]

  show raw: set text(font: code-font, size: 8.5pt)

  [
    #align(center)[
      #text(font: title-font, size: 16pt, weight: "bold")[#title]
      #if subtitle != none [
        #v(0.35em)
        #text(font: title-font, size: 10pt, fill: rgb("#4d4d4d"))[#subtitle]
      ]
      #v(0.7em)
      #text(font: title-font, size: 11pt, weight: "semibold")[#authors]
      #if affiliation != none [
        #linebreak()
        #text(size: 9pt, style: "italic")[#affiliation]
      ]
      #if email != none [
        #linebreak()
        #text(size: 9pt)[#email]
      ]
    ]

    #v(0.9em)
    #align(center)[#text(font: title-font, size: 11pt, weight: "bold")[
      #if lang == "zh" [摘要] else [Abstract]
    ]]
    #v(0.2em)
    #block(inset: (x: 0.25in, y: 0pt))[#abstract]

    #v(0.5em)
    #if keywords != () [
      #text(font: title-font, size: 10pt, weight: "bold")[
        #if lang == "zh" [关键词] else [Keywords]
      ]: #keywords
    ]

    #v(0.75em)
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

#let bnf-table(rows) = box(width: 100%)[
  #table(
    columns: (1.5fr, 0.6fr, 2.35fr, 1.75fr),
    align: (right, left, left, left),
    inset: (x: 5pt, y: 2pt),
    stroke: none,
    ..rows,
  )
]
