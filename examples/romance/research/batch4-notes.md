# Batch 4 (verbs): disagreements and judgement calls

13 verbs × 11 cells × 4 stages. `stare` has no `french` rows (see below), so
the batch has 561 rows. `cantare`, `amare` and `habere` replace the pilot's
rows for those verbs. They are in the new format and add PRET.3SG, PTCP and
the full present.

## Sources actually consulted (full text)
- **NyropII**: Nyrop, *Grammaire historique* t. II (morphologie), archive.org
  `grammairehistori02nyrouoft`. The cited sections are §24, §26 (apophony),
  §53 (3sg -t), §54-56 (-ons, -ez), §60 (-ont), §72-74 (infinitives),
  §116 (aller, ester), §119 (dico, sum), §120-127 (presents with yod:
  muir, ai, puis, faz), §166 (ester perfect), §182, §189-191 (strong
  perfects), §206-210 (futures). NyropI §200 is cited at second hand from
  the pilot.
- **Bourciez**: *Précis historique de phonétique française*,
  `prcishistoriqu00bouruoft`. §157 covers s before a consonant and §54
  covers ei > oi.
- **PidalManual**: Menéndez Pidal, *Manual elemental*,
  `manualelementald00menuoft`. The cited sections are §10, §31.2 (seer,
  veer), §39, §113-116 (presents, including the irregular ones in §116),
  §118-122 (perfect and participle).
- **PidalCid**: Menéndez Pidal, *Cantar de mio Cid* vol. I (grammar),
  `cantardemocidte00pidagoog`. The cited sections are §77, §81-83, §88
  (irregular presents: ser, aver, fazer, ir, dar, estar), §93-98 (perfects
  and participles) and §99 (future). Numbers after a form are Pidal's
  verse numbers.
- **Cid text**: the paleographic and critical text, `CantarDeMioCidMenend3`.
  "(Nx)" counts come from grep over the paleographic part, which uses long
  ſ, so for example *sera* shows up as "fera". The counts are approximate.
  They include a few hits from the apparatus, and some words are
  ambiguous (*yra* means both 'anger' and 'will go').
- **Wiktionary** (en): the OF conjugation tables for chanter, amer, avoir,
  estre, faire, dire, venir, tenir, veoir, pooir, aler, ester and morir; the
  OSp conjugation tables for cantar, aver and seer (the others have no
  table); and the pages for individual forms (sui, vois, vint, vit, mort,
  esté, sido, soy, voy, vamos, eres, hemos, été, aller, vais, suis, fit).

I did not consult Darmesteter, NyropI, fr/es Wiktionary or any dictionary
for this batch. The Darmesteter, NyropI and WP references in the
`cantare`/`amare` rows are carried over unchanged from the pilot. I could not reach Pope, Penny, Lloyd, DCECH, CORDE or TLFi.
"standard" in the source column means the modern standard paradigm.

## Policy on `kind` and the `latin` column
- `latin` gives the form each reflex actually continues. That can be a VL
  form (*vao, *aunt, *sutis, *potēre, *morīre), a form of another verb
  (sedēre, stātum, vādō, fuit) or a periphrasis for the future
  (*cantāre habeō*).
- `kind` is judged against the **entry's** verb. `replaced` means the
  form comes from another verb (sedēre, stāre, vādere, *allāre/ambulāre,
  or fuit for `ire`). `analogical` means a form of the same verb that is
  not the regular reflex: VL reshapings (*essere, *sutis, *morīre, the
  -ūtum participles), levelling (fizo, vino, dicho, tovo, tengo/vengo,
  -ons, -ez), or a Latin future pressed into service as a present (eres).
  The VL contracted auxiliary forms of habere (*ayo, *has, *hat, *hant;
  OF *ajo, *at, *aunt) are marked `inherited`. They are reductions and
  not analogies, and the handbooks treat them as the etymon.
- Modern forms that inherit an earlier analogy keep `analogical`: hizo,
  suis, dicho and the like.
- **-ons.** Every OF and French 1pl in -ons is `analogical`, since
  -ons < *-umus (NyropII §54-55). The pilot only put this in a note.
- **-ez.** OF -ez in non-a verbs (venez, tenez, morez, avez, poez, veez) is
  `analogical`, following NyropII §56: "-ez ... remonte à -atis, et a
  remplacé, par analogie, les autres terminaisons".

## Disagreements between sources
1. **OF ester present.** NyropII's table (§116.2) gives 1sg *estais* and 3pl
   *estant*. His own §60 says "on avait encore estont de ester", and
   Wiktionary gives *estois … estont*. I took estois (low) and estont. By
   analogy with *vois* < *vao + -is, I'd expect *estois*.
2. **Futures of veoir.** Nyrop §208.5 has *verrai* (regular from *videraio).
   Wiktionary has *verai*. I took verrai.
3. **OF 2pl of -ēre verbs.** Nyrop gives *aveiz*, *poeiz*. Wiktionary gives
   *avez*, *poez*. Both spellings are in the TSV and I used /-ets/ for the
   IPA. Whether Francien in 1150 had -eiz, -oiz or -ez here is not settled.
4. **Spanish *vamos*.** PidalManual §116.5 derives it from a VL indicative
   *vamus. Wiktionary derives it from the subjunctive vādāmus. Either way
   it replaced OSp *imos*.
5. **French *aller*.** Nyrop's table assumes *ambulāre / *allāre. Wiktionary
   says "Early Medieval Latin alāre, of uncertain origin". The latin column
   says "*allāre (? < ambulāre)".
6. **OF 3sg of aler.** Nyrop (§116.1c) says *vait* is the oldest form (Alexis,
   Roland) and that *vait, vat, va* co-existed. I gave *va* /va/ and listed
   vait in the spelling. Use /vajt/ if you prefer the older form.
7. **OSp *fue* vs *fo*.** Per Abbat always writes *fue*. Pidal (§95.4)
   argues from the assonance in ó that the poet said *fo* (< *fut, attested
   in Sahagún 1196). The row gives *fue* /fwé/, since that is the MS form
   and the one that continued.
8. **OSp ser and ver.** The MS writes *ser*, *ver*. Pidal (PidalManual
   §31.2, PidalCid) says the 13th c. still said *seer*, *veer* in two
   syllables. I gave seer /seéɾ/ and veer /βeéɾ/. The same applies to
   *vedes* (MS) vs *veedes*.
9. **Wiktionary's OSp tables are unreliable here.** The *aver* table stars
   *e* and *a* and gives *aves/ave* as the main forms, while Pidal has
   *he/ha* as the normal Cid forms. The *ser* page shows the paradigm of
   *seer* 'to sit'. I followed Pidal.

## Judgement calls
- **`stare`, French.** Modern French has no reflex of *ester* as a verb,
  so there are no french rows. Its participle *esté* survives as *été*,
  the participle of *être*. That form is in the `esse` PTCP row with
  `latin` stātum and `kind` replaced. The OF *ester* rows are kept; OF
  *estre* had already started to take over its forms (Wiktionary).
- **OSp initial v-** is written /β/ (βeníɾ, βó, βeéɾ), following
  Wiktionary's OSp transcriptions and the traditional view that b-/v-
  were distinct. Medial -v- and -b- are /β/ as in the pilot.
- **OSp uo vs ue.** Pidal (§81) reads the rhyme of *puede* (v. 116) as
  *puode*. I wrote ue throughout, as in the pilot.
- **OF final -t.** Following NyropII §53, -t is gone after e and a (chante,
  a, va, esta, chanta) and after unsupported i and u (fu, moru). It is
  kept where it was checked early: dit, fait, voit, vient, puet, est, ot,
  pot, estut, vint, vit.
- **OF s before t** (estre, est, estes, fist, dist, ester) is still
  pronounced. Bourciez §157 says that by the end of the 11th c. s survived
  only before voiceless stops, and was gone before every consonant a
  century later.
- **OF ai.** As in the pilot, /aj/ is kept in faire, fait, faites, faimes,
  vait and the -ai of the future, all flagged. Nyrop has verb-final ai
  rhyming with é from the 13th c.
- **OF ui** (sui, puis, muir) is written /yj/, following Wiktionary *sui*
  (early /ˈsyi̯/).
- **OF -ng** (vieng, tieng) is written /ɲ/ with low confidence. It may
  already have been /n/.
- **OF pretonic o** (pooir, morir, poons, morons) is written /o/, as with
  the pilot's -ons. Wiktionary writes /u/.
- **OF dimes vs disons.** Nyrop has dimes in the Alexis and in Philippe de
  Thaon, and says it gave way early to disons. I gave dimes with low
  confidence.
- **OF future of estre.** The old future *ier/iert* (< erō, erit) is
  probably still the commonest form c.1150 (Roland). I gave *serai/sera*,
  which is the form that continued, and noted iert.
- **OSp fazer.** The Cid has *femos* (once) and *feches* (11x), keeping the
  Latin stress (PidalCid §88.5). *fazemos* does not occur, and *fazedes*
  occurs only twice. The future is built on short *far* (faré, fará).
- **OSp estar PRET.** *estido* (Cid 3030) competes with *estudo* and *estovo*
  in the 13th c. I gave estido.
- **Forms not found in the Cid** are given with `medium` confidence from
  Pidal's regular paradigms and say so in the note. They include fazes,
  vienes, venimos, puedes, vees, veemos, veen, estamos, estaré, and the
  whole OSp present of morir except morir/murir itself. OSp *avido*,
  *podido*, *seído* and *murió/morió* are `low`. I found no c.1200
  attestation for them, only the general rules (*seído* from Wiktionary
  *sido*).
- **French mourrai/mourra** are written with long /ʁʁ/, following the
  dictionaries' careful pronunciation. *pourrai* has a single ʁ.
- **French 1sg -s** (dis, vois, viens) is spelling only. The sound is the
  regular reflex, so these rows are `inherited`. *fais, meurs, peux* and
  *vais* are `analogical` because their sound is not regular.
