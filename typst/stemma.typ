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
//   #notes("ir", stage: "azal")            ... those in force at a stage
//   #entry("ir", "azal")                   a dictionary entry
//   #dictionary("azal")                    every entry with a reflex there
//   #dictionary("azal", fields: ("head", "gender", "gloss"))
//                                          ... showing only these, in order
//   #dictionary("azal", bound: false)      ... leaving out bound roots (ber-)
//   #paradigm("ir", "azal")                a table of the cells, one row per
//                                          member of the last dimension
//   #paradigm("ir", "azal", rows: "number")   ... or of another dimension
//
// Forms are set with `form-style` (italic), and dictionary headwords with
// `head-style` (bold, upright: the bundled Libertinus Serif has no IPA in
// bold italic). `form-font` sets a font for every form, such as SIL's
// Charis, made for IPA ("Charis SIL" before version 7), which has it in
// every style:
//
//   #let (..) = stemma(json("build/lexicon.json"), form-font: "Charis",
//     head-style: x => strong(emph(x)))
//
// An entry shows `fields`, in order: "head", "category", "properties" (all
// of them, such as gender), "gloss", "etymology", "source" and "notes"
// (those in force at the stage); the name of one property; or a function
// of the entry's id and the stage that gives content. `property-style`
// sets how a property's value is shown.

#let stemma(
  lex,
  form-style: emph,
  head-style: strong,
  form-font: none,
  fields: ("head", "category", "properties", "gloss", "etymology", "source", "notes"),
  property-style: (name, value) => emph(value),
) = {
  let entry-fields = fields
  let in-font(body) = if form-font == none { body } else { text(font: form-font, body) }
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
  // parent, and fields that repeat the forms. It always gives the stage
  // where an item comes into being on a line (where it is formed, or where
  // a cell is joined on another line), so the nearest one on the way back
  // to the root is the reflex here.
  let rx(it, stage) = {
    let r = path(stage).rev().map(s => it.reflexes.at(s, default: none)).find(r => r != none)
    if r == none { return none }
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
      // A reflex gives a gloss only where it differs from the item's.
      gloss: r.at("gloss", default: it.gloss),
    )
  }

  // The forms of an item on the way to a stage, nearest first, as stage and
  // item: where a cell continues another (`continues`), the other one's
  // above where it is joined.
  let lineage(id, stage) = {
    let out = ()
    let cur = item(id)
    for s in path(stage).rev() {
      if rx(cur, s) == none { break }
      out.push((s, cur.id))
      let p = stage-info.at(s).parent
      let next = cur.at("continues", default: (:)).at(s, default: none)
      if p != none and next != none and rx(cur, p) == none { cur = item(next) }
    }
    out
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
    in-font(form-style(if star { "*" + t } else { t }))
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

  // Notes are runs of text and forms: one list for every stage, or one
  // from each of some stages on, each in force down its own line.
  let note(runs) = for run in runs {
    if "text" in run {
      // Single newlines from YAML block scalars are spaces; blank lines
      // are paragraph breaks.
      run.text.split("\n\n").map(p => p.replace("\n", " ")).join(parbreak())
    } else { style((run.form,), run.star) }
  }
  // The notes in force at a stage, or with no stage all of them, in stage
  // order, each rendered.
  let note-list(id, stage) = {
    let it = item(id)
    if it.notes == none { return () }
    if type(it.notes) == array { return (note(it.notes),) }
    let stages = if stage == none { lex.stages.map(s => s.id) } else { path(stage) }
    stages.filter(s => s in it.notes).map(s => note(it.notes.at(s)))
  }
  let notes(id, stage: none) = {
    let all = note-list(id, stage)
    if all.len() == 0 { none } else { all.join(parbreak()) }
  }

  // The properties in force at a stage, such as gender: lexicon.json gives
  // them where they change.
  let properties-at(it, stage) = {
    let ps = it.at("properties", default: (:))
    path(stage).rev().map(s => ps.at(s, default: none)).find(p => p != none)
  }

  let entry(id, stage, fields: entry-fields) = {
    let it = item(id)
    let r = rx(it, stage)
    let hd = head-item(it, stage)
    let cited = rx(hd, stage)
    let head = if cited.spelled != none { cited.spelled.join(" ~ ") } else { cited.forms.join(" ~ ") }
    // Etymology: the forms of the cited item on the way here, and of what
    // it continues, nearest stage first; stages where the form did not
    // change are skipped.
    let earlier = lineage(hd.id, stage).slice(1)
    let forms-of(((s, x))) = rx(item(x), s).forms
    let shown = earlier.enumerate().filter(((k, e)) => {
      k + 1 == earlier.len() or forms-of(e) != forms-of(earlier.at(k + 1))
    }).map(((k, e)) => e)
    let chain = shown.map(((s, x)) => {
      let info = stage-info.at(s)
      let abbr = if info.abbr != none { info.abbr } else { info.name }
      [#abbr #reflex(x, s)]
    })
    let props = properties-at(it, stage)
    let prop(name) = {
      let v = if props == none { none } else { props.at(name, default: none) }
      if v != none { property-style(name, v) }
    }
    // Fields on the entry's line, and notes in a paragraph below it.
    let line = ()
    let below = ()
    for f in fields {
      if type(f) == function { line.push(f(id, stage)) }
      else if f == "head" { line.push(in-font(head-style(head))) }
      else if f == "category" { if r.category != none { line.push(smallcaps(lower(r.category))) } }
      else if f == "properties" {
        if props != none { for name in props.keys().sorted() { line.push(prop(name)) } }
      }
      else if f == "gloss" { if r.gloss != none { line.push(["#r.gloss"]) } }
      else if f == "etymology" { if chain.len() > 0 { line.push([< #chain.join([ < ])]) } }
      else if f == "source" { if it.source != none { line.push([(#it.source)]) } }
      else if f == "notes" {
        for n in note-list(id, stage) { below.push(par(text(size: 0.9em, n))) }
      }
      else { let v = prop(f); if v != none { line.push(v) } }
    }
    block(breakable: false, {
      line.join([ #h(0.3em)])
      for b in below { b }
    })
  }

  // Bound entries are cited with a hyphen (ber-). An entry with a paradigm
  // is always listed, since it is cited by a cell (its `cite`).
  let dictionary(stage, kinds: ("root", "derivative"), bound: true, fields: entry-fields) = {
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
    for i in ids.sorted(key: key) { entry(i, stage, fields: fields) }
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
      // The paradigm's cells, and any the entry adds that exist here.
      let added = it.cells.map(c => c.slice(id.len() + 1)).filter(c => not c.contains("~")
        and c not in pd.cells and rx(item(id + "." + c), stage) != none
        and rx(item(id + "." + c), stage).forms != none)
      let names = pd.cells.filter(c => not c.contains("~")) + added
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
