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

  // An item, with the fields lexicon.json leaves out when empty.
  let item(id) = {
    let it = lex.items.at(id, default: none)
    assert(it != none, message: "stemma: unknown item " + id)
    (
      bound: false, owner: none, gloss: none, source: none, paradigm: none,
      variant: none, variant_of: none, notes: none,
      cells: (), repatterns: (), category: (), fate: (:), cite: (:),
    ) + it + (id: id)
  }

  // The reflex of an item at a stage, or none where the item doesn't exist.
  // lexicon.json leaves out a stage whose reflex is the same as at its
  // parent, and fields that repeat the forms.
  let rx(it, stage) = {
    let line = path(stage)
    let from = line.position(s => s == it.formed)
    if from == none { return none }
    let r = line.slice(from).rev().map(s => it.reflexes.at(s, default: none)).find(r => r != none)
    let lost = r.at("lost", default: false)
    let forms = r.at("forms", default: none)
    let spelled = r.at("spelled", default: forms)
    let regular = r.at("regular", default: forms)
    (
      forms: forms,
      spelled: spelled,
      regular: regular,
      regular_spelled: r.at("regular_spelled", default: if lost { regular } else { spelled }),
      category: r.at("category", default: none),
    )
  }

  // The item an entry is cited by at a stage, as a headword: lexicon.json's
  // cite gives it where it changes. Where that has no form, the entry itself.
  let head-item(it, stage) = {
    let c = path(stage).rev().map(s => it.cite.at(s, default: none)).find(c => c != none)
    let r = if c == none { none } else { rx(item(c), stage) }
    if r == none or r.forms == none { it } else { item(c) }
  }

  let style(forms, star) = {
    if forms == none or forms.len() == 0 { return [—] }
    let t = forms.join(" ~ ")
    form-style(if star { "*" + t } else { t })
  }

  let reflex(id, ..args, phonemic: false, regular: false) = {
    let it = item(id)
    let pos = args.pos()
    let stage = if pos.len() > 0 { pos.at(0) } else { it.formed }
    let r = rx(it, stage)
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
    let it = item(id)
    if it.notes == none { return none }
    for run in it.notes {
      if "text" in run {
        // Single newlines from YAML block scalars are spaces; blank lines
        // are paragraph breaks.
        run.text.split("\n\n").map(p => p.replace("\n", " ")).join(parbreak())
      } else { style((run.form,), run.star) }
    }
  }

  let entry(id, stage) = {
    let it = item(id)
    let r = rx(it, stage)
    let hd = head-item(it, stage)
    let cited = rx(hd, stage)
    let head = if cited.spelled != none { cited.spelled.join(" ~ ") } else { cited.forms.join(" ~ ") }
    // Etymology: the forms of the cited item on the way here, from where it
    // was formed.
    let line = path(stage)
    let from = line.position(s => s == hd.formed)
    // Nearest stage first; stages where the form did not change are skipped.
    let earlier = line.slice(from, line.len() - 1).rev()
    let shown = earlier.enumerate().filter(((k, s)) => {
      let next = if k + 1 < earlier.len() { earlier.at(k + 1) } else { none }
      next == none or rx(hd, s).forms != rx(hd, next).forms
    }).map(((k, s)) => s)
    let chain = shown.map(s => {
      let info = stage-info.at(s)
      let abbr = if info.abbr != none { info.abbr } else { info.name }
      [#abbr #reflex(hd.id, s)]
    })
    block(breakable: false, {
      strong(form-style(head))
      if r.category != none { [ #h(0.3em) #smallcaps(lower(r.category))] }
      if it.gloss != none { [ #h(0.3em) "#it.gloss"] }
      if chain.len() > 0 { [ #h(0.3em) < #chain.join([ < ])] }
      if it.source != none { [ (#it.source)] }
      if it.notes != none { par(text(size: 0.9em, notes(id))) }
    })
  }

  // Bound entries are cited with a hyphen (ber-). An entry with a paradigm
  // is always listed, since it is cited by a cell (its `cite`).
  let dictionary(stage, kinds: ("root", "derivative"), bound: true) = {
    let ids = lex.order.filter(i => {
      let it = item(i)
      let r = rx(it, stage)
      (bound or not it.bound or it.cells.len() > 0) and it.kind in kinds and r != none and r.forms != none
    })
    let key(i) = {
      let it = item(i)
      let r = rx(head-item(it, stage), stage)
      if r.spelled != none { r.spelled.at(0, default: "") } else { "" }
    }
    for i in ids.sorted(key: key) { entry(i, stage) }
  }

  // Cells as a table. Rows are the members of one dimension, columns every
  // combination of the others. Cells not in the product of the dimensions
  // are not shown; a missing cell shows as —. Variants are shown under
  // their main cell.
  let paradigm(id, stage, rows: auto) = {
    let it = item(id)
    assert(it.paradigm != none, message: "stemma: " + id + " has no paradigm")
    // The paradigm in force at the stage: the nearest repattern on the way
    // there, if any.
    let line = path(stage)
    let pname = it.paradigm
    let depth = -1
    for rp in it.repatterns {
      let d = line.position(s => s == rp.at)
      if d != none and d > depth { pname = rp.paradigm; depth = d }
    }
    let pd = lex.paradigms.at(pname)
    let dims = pd.dimensions
    let form(cid) = {
      let r = if cid in lex.items { rx(item(cid), stage) } else { none }
      if r == none or r.forms == none { [—] } else { reflex(cid, stage) }
    }
    // A cell, with its variants (CELL~label) below it.
    let cell(name) = {
      let cid = id + "." + name
      let variants = it.cells.filter(c => c.starts-with(cid + "~"))
      form(cid)
      for v in variants {
        linebreak()
        text(size: 0.8em)[#v.slice(cid.len() + 1): #form(v)]
      }
    }
    if dims.len() == 0 {
      let names = it.cells.map(c => c.slice(id.len() + 1)).filter(c => not c.contains("~"))
      return table(columns: 2, ..names.map(c => ([#c], cell(c))).flatten())
    }
    let r = if rows == auto { dims.len() - 1 } else { dims.position(d => d.name == rows) }
    assert(r != none, message: "stemma: " + pname + " has no dimension " + repr(rows))
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
