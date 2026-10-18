// Typst helpers for a stemma build.
//
//   #import "stemma.typ": stemma
//   #let (reflex, notes, entry, dictionary) = stemma(json("build/lexicon.json"))
//
//   #reflex("ir.DIR", "azal")              → _iš_
//   #reflex("ir")                          → _\*ir₁_ (where it was formed)
//   #reflex("ir.DIR", "azal", regular: true)   the regularly expected form
//   #reflex("ir.DIR", "azal", phonemic: true)  unspelled
//   #notes("ir")                           the item's notes, forms resolved
//   #entry("ir", "azal")                   a dictionary entry
//   #dictionary("azal")                    every entry with a reflex there
//   #dictionary("azal", bound: false)      ... leaving out bound roots (ber-)
//   #paradigm("ir", "azal")                a table of the cells, one row per
//                                          member of the last dimension
//   #paradigm("ir", "azal", rows: "number")   ... or of another dimension

#let stemma(lex, form-style: emph) = {
  let stage-info = (:)
  for s in lex.stages { stage-info.insert(s.id, s) }

  // Stages from the root down to `s`.
  let path(s) = {
    let out = ()
    let cur = s
    while cur != none {
      out.insert(0, cur)
      cur = stage-info.at(cur).parent
    }
    out
  }

  let style(forms, star) = {
    if forms == none or forms.len() == 0 { return [—] }
    let t = forms.join(" ~ ")
    form-style(if star { "*" + t } else { t })
  }

  let reflex(id, ..args, phonemic: false, regular: false) = {
    let item = lex.items.at(id, default: none)
    assert(item != none, message: "stemma: unknown item " + id)
    let pos = args.pos()
    let stage = if pos.len() > 0 { pos.at(0) } else { item.formed }
    let r = item.reflexes.at(stage, default: none)
    assert(r != none, message: "stemma: " + id + " has no reflex at " + stage)
    let star = stage == lex.root
    let forms = if regular {
      if phonemic or star { r.regular } else { r.regular_spelled }
    } else {
      if phonemic or star { r.forms } else { r.spelled }
    }
    assert(forms != none, message: "stemma: " + id + " is lost at " + stage
      + " (use regular: true for the would-be form)")
    style(forms, star)
  }

  let notes(id) = {
    let item = lex.items.at(id)
    if item.notes == none { return none }
    for run in item.notes {
      if "text" in run {
        // Single newlines from YAML block scalars are spaces; blank lines
        // are paragraph breaks.
        run.text.split("\n\n").map(p => p.replace("\n", " ")).join(parbreak())
      } else { style((run.form,), run.star) }
    }
  }

  let entry(id, stage) = {
    let item = lex.items.at(id)
    let r = item.reflexes.at(stage)
    // An entry with a paradigm is cited by its first cell.
    let cited = if item.cells.len() > 0 { lex.items.at(item.cells.at(0)).reflexes.at(stage) } else { r }
    let head = if cited.spelled != none { cited.spelled.join(" ~ ") } else { cited.forms.join(" ~ ") }
    // Etymology: the forms on the way here, from where the item was formed.
    let line = path(stage)
    let from = line.position(s => s == item.formed)
    // Nearest stage first; stages where the form did not change are skipped.
    let earlier = line.slice(from, line.len() - 1).rev()
    let shown = earlier.enumerate().filter(((k, s)) => {
      let next = if k + 1 < earlier.len() { earlier.at(k + 1) } else { none }
      next == none or item.reflexes.at(s).forms != item.reflexes.at(next).forms
    }).map(((k, s)) => s)
    let chain = shown.map(s => {
      let info = stage-info.at(s)
      let abbr = if info.abbr != none { info.abbr } else { info.name }
      [#abbr #reflex(id, s)]
    })
    block(breakable: false, {
      strong(form-style(head))
      if r.category != none { [ #h(0.3em) #smallcaps(lower(r.category))] }
      if item.gloss != none { [ #h(0.3em) "#item.gloss"] }
      if chain.len() > 0 { [ #h(0.3em) < #chain.join([ < ])] }
      if item.source != none { [ (#item.source)] }
      if item.notes != none { par(text(size: 0.9em, notes(id))) }
    })
  }

  // Bound entries are cited with a hyphen (ber-). An entry with a paradigm
  // is always listed, since it is cited by its first cell.
  let dictionary(stage, kinds: ("root", "derivative"), bound: true) = {
    let ids = lex.order.filter(i => {
      let it = lex.items.at(i)
      (bound or not it.bound or it.cells.len() > 0) and it.kind in kinds and it.reflexes.at(stage, default: (forms: none)).forms != none
    })
    let key(i) = {
      let it = lex.items.at(i)
      let r = if it.cells.len() > 0 { lex.items.at(it.cells.at(0)).reflexes.at(stage) } else { it.reflexes.at(stage) }
      if r.spelled != none { r.spelled.at(0, default: "") } else { "" }
    }
    for i in ids.sorted(key: key) { entry(i, stage) }
  }

  // Cells as a table. Rows are the members of one dimension, columns every
  // combination of the others. Cells not in the product of the dimensions
  // are not shown; a missing cell shows as —.
  let paradigm(id, stage, rows: auto) = {
    let item = lex.items.at(id)
    assert(item.paradigm != none, message: "stemma: " + id + " has no paradigm")
    let pd = lex.paradigms.at(item.paradigm)
    let dims = pd.dimensions
    let cell(name) = {
      let r = lex.items.at(id + "." + name, default: (reflexes: (:))).reflexes.at(stage, default: none)
      if r == none or r.forms == none { [—] } else { reflex(id + "." + name, stage) }
    }
    if dims.len() == 0 {
      return table(columns: 2, ..pd.cells.map(c => ([#c], cell(c))).flatten())
    }
    let r = if rows == auto { dims.len() - 1 } else { dims.position(d => d.name == rows) }
    assert(r != none, message: "stemma: " + item.paradigm + " has no dimension " + repr(rows))
    let others = range(dims.len()).filter(k => k != r)
    let combos = ((),)
    for k in others {
      let next = ()
      for c in combos { for m in dims.at(k).members { next.push(c + (m,)) } }
      combos = next
    }
    // The cell name: members in dimension order.
    let name(m, combo) = range(dims.len()).map(k =>
      if k == r { m } else { combo.at(others.position(o => o == k)) }).join(".")
    table(
      columns: combos.len() + 1,
      [], ..combos.map(c => strong(c.join("."))),
      ..dims.at(r).members.map(m => (strong(m), ..combos.map(c => cell(name(m, c))))).flatten(),
    )
  }

  (reflex: reflex, notes: notes, entry: entry, dictionary: dictionary, paradigm: paradigm)
}
