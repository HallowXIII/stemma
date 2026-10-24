# Batch 1: first- and second-declension nouns. Disagreements and judgement calls

296 rows for 29 entries, in the CONVENTIONS.md format. murus, terra and capra
repeat the pilot's values in the new format, with modern forms now sourced to
Wiktionary instead of "standard".

## Sources consulted (full text)
- The pilot's archive.org texts: **NyropI**, **NyropII**, **Bourciez**,
  **Darmesteter**, **PidalManual**, **PidalCid** (grammar, `cantardemocidte00pidagoog`)
  and the **Cid text** (`CantarDeMioCidMenend3`). That file holds both the
  paleographic and the critical text, and the OCR reads long s as f. So the
  Cid counts in the TSV ("~N") are counts over both texts, as in the pilot.
  They show that a form occurs, not how often.
- en.wiktionary (OF and Spanish entries) and fr.wiktionary (French entries,
  whose etymologies cite TLFi, DAF9 and DÉCT).
- **Not reachable**: CNRTL/TLFi (a JS app), DCECH, CORDE, Pope, Penny, Zink.
  None of the TSV's dates comes from them directly.

## Disagreements between sources
1. **OF reflex of *oculus*, cas sujet and oblique plural.** Bourciez (§190
   Rem. I, §70 Rem. I) has *uelz* and then *ueus*, with l vocalised. Nyrop's
   parallel *dueil* (II §267.2) has the cas sujet *duez*, with no u.
   en.wiktionary gives *ialz*. I wrote /wɛuts/ with low confidence.
2. **OF *focus*.** Darmesteter has *fou* > *feu* "about the same period" as
   ou > eu. Bourciez (§69 Rem. III) has a triphthong, *\*fuou > \*fœw > fœ*.
   fr.wiktionary gives *fou* (9th c.), *fu* and *foc*. I wrote /fou/, which
   fits the convention's "ou for ō, ŭ" spelling, with low confidence.
3. **OF *digitus*.** fr.wiktionary (after DAF9) gives *dei/doi* < \**dĭtus*,
   with no t. en.wiktionary's headword is *doit*, with variants *dei, deit, doi*.
   I wrote /doj/ (ei > oi, as in the pilot's *avoir*) with low confidence.
4. **OF *rota*.** Nyrop (I §177) says *roue* was once *ruee*. Bourciez (§66)
   gives the regular form as *reue*, which is the later stage after ue > eu.
   en.wiktionary has *roe*. I wrote /rwɛə/ with low confidence. Nyrop and
   Bourciez also disagree on the model for French *roue*: *rouer* for Nyrop,
   *rouelle* for Bourciez. Either way the row is `analogical`.
5. **OF *aqua*.** Nyrop (I §199) has *aive* > *eve*. Bourciez (§38 Rem. V) has
   *ewe* > *\*eawe* > *eaue*. en.wiktionary uses *iaue* as its headword and
   lists *ewe*. I wrote /ewə/ with low confidence. *aigue* is southern.
6. **OF *chose*.** en.wiktionary gives /tʃozə/, with a close o. Bourciez (§83)
   says au gave an open ǫ in the oldest French, and that it closed before s
   only later (Rem. I). I wrote /tʃɔzə/.
7. **OF *langue*.** en.wiktionary gives /lenɡʷə/ (archaic) and /lanɡ(ʷ)ə/
   (classical). Bourciez (§137) says the w of gw "did not disappear completely,
   before a at least, until the end of the 12th c.". I wrote /langə/. /langwə/
   is defensible.
8. **French *loup*.** Nyrop (I §182) attributes it to the analogy of *louve*.
   fr.wiktionary attributes it to eastern dialect *lou* combined with that
   analogy. Both agree that the Francien reflex was *leu*.
9. **Is *escole* learned or semi-learned?** Nyrop and Bourciez list *école*
   among "mots d'emprunt", and en.wiktionary calls OF *escole* a learned
   borrowing. I chose `semi-learned`: the word has a popular prothetic e but
   lacks the expected diphthong (\**escuele*). Spanish *escuela* has the
   diphthong and is `inherited`.

## Judgement calls
- **l vocalisation** (chevaus, chasteaus, ueuz). Bourciez (§188) says it was
  complete in the North "vers 1100", although 12th-c. MSS still write l. So I
  wrote /aws/ and /ɛaws/ and gave *chevals* and *chastels* as spellings only.
- **en/an.** Bourciez (§61) dates the merger in the Île-de-France to about the
  mid-11th c., so *tens* is /tans/ and *langue* /langə/. Nasalisation is left
  unmarked, as the conventions require.
- **ei > oi** (estoile, doi): /oj/, as in the pilot's *avoir*. /ej/ is the
  older value.
- **Preconsonantal s before voiceless stops** (chastel, estoile, escole). Bourciez
  (§157 hist.) says it still sounded at the end of the 11th c. and was gone
  about a century later. I kept /s/ for 1150.
- **Final t in *lit*** (< ct) is kept as /lit/. The convention's "final -t
  after a vowel is gone" concerns Latin single intervocalic or final t, which
  passed through θ. It does not apply to t from ct or tt.
- **ou vs eu** (lou, fou): /ou/, following the convention. Bourciez (§72) dates
  ou > eu to the second half of the 12th c.
- **OF cas sujet forms not quoted from a text.** Some come only from the
  paradigm type: *fers*, *liz*, *dois*, *chiés*. Nyrop gives *chies* explicitly.
  The others are formed by Nyrop's rules (§§252, 266, 268), and I gave them
  medium or low confidence.
- **populus.** OF *pueple* and French *peuple* are `semi-learned`. The ŏ
  diphthongised, but p replaced the expected b: fr.wiktionary gives *poblo*
  (842) and *poble/pueble* (980) before *pueple*. Spanish *pueblo* is regular.
- **caput.** OF *chief* (< \*capum, Nyrop II §246) fills the four cells. French
  *chef* is inherited but now means 'chief'. French *tête* (< testa) and
  Spanish *cabeza* (< \*capitia, Cid *cabeça*) are `replaced` rows that carry
  their own etyma in `latin`. OSp *cabo* in the Cid mostly means 'end' or
  'beside', not 'head'. OF *teste* already competes with *chief* in the 12th c.
  I gave it no row because it is not in the brief.
- **filius.** French *fils* continues the OF cas sujet *fiz*, so its
  ACC.SG/ACC.PL rows are `derived`. The cas régime *fil* /fiʎ/ died out.
  Bourciez (§160 Rem. I) says the final s was pronounced again only from the
  18th c.
- **French *yeux*** continues the OF plural, not *œil* + s. The row is
  `inherited` and says so in its note.
- **folia** is given as a feminine noun: OF *fueille(s)*, OSp *foja(s)*
  (Pidal: "folia, ant. foja, mod. hoja") and French *feuille(s)*.
- **stella, OSp.** The r is unetymological. Pidal (Manual) treats it as
  epenthetic r "above all after st", and Wiktionary posits a regional
  \**strēlla*. It is already present in the Auto de los Magos (*strela*) and
  the Cid (MS *estrelas*, v. 332). Both texts write a single l. Pidal notes
  that Per Abbat often writes l for ll, so I wrote /ʎ/, with medium confidence.
  The e does not diphthongise (\*stēlla).
- **schola, OSp.** The Cid has only *escuellas* ('retinue'), and Pidal calls
  the ll "inexplicable". I wrote /eskwéla(s)/ and noted /eskwéʎas/. The
  singular *escuela* is not in the Cid, so it is `medium`.
- **OSp *vidas*.** In the Cid this is the name of the moneylender (Rachel e
  Vidas), so the plural row rests on Pidal alone.
- **OSp *dedos*.** The text index lists *dedos*, but the occurrence is *De dos*.
  *dedo* is not in the Cid.
- **OSp labials.** I wrote /b/ for b < -p- (lobo, cabo, pueblo, cabra) and /β/
  for v/u (cavallo, vida, yerva), following the conventions. *yerva/yerba*
  varies in spelling after r.
- **Spanish initial hie-** (hierro, hierba) is written /ʝe/, since the
  conventions keep ʝ apart from ʎ.
- **Old Spanish rows not in the Cid** (muro, lobo, fuego, dedo, lecho, tiempo,
  rueda, foja, yerva, and the plurals of pueblo, luna, lengua, cabo) are
  `medium`. The forms are not in doubt, but I did not check them in a text
  dated about 1200.
