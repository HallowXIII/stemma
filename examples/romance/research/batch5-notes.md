# Batch 5: thirteen verbs. Disagreements and judgement calls

609 rows for 14 ids: lavare, dormire, audire, vendere, credere, bibere,
legere, mittere, sapere, cadere, placere, clamare, pensare (inherited
Sp *pesar*, Fr *peser*) and pensare-l (semi-learned Sp *pensar*, Fr *penser*).
The cells are INF, PRS.1SG–3PL, FUT.1SG, FUT.3SG, PRET.3SG and PTCP at
old-spanish, spanish, old-french and french. Two kinds of gap are deliberate:
- OSp *plazer* has rows only for INF, PRS.3SG, PRS.3PL, FUT.3SG, PRET.3SG and
  PTCP. The verb is impersonal in the Cid (*plaze*, *plaz me*), and I found no
  personal forms from about 1200.
- French *choir* has no 1PL or 2PL row. fr.wiktionary greys out *choyons* and
  *choyez* as unused.

## Sources consulted (full text)
- archive.org: **NyropII** (`grammairehistori02nyrouoft`), **Bourciez**
  (`prcishistoriqu00bouruoft`), **PidalManual** (`manualelementald00menuoft`),
  **PidalCid** grammar (`cantardemocidte00pidagoog`) and the **Cid text**
  (`CantarDeMioCidMenend3`, file `Cantar_de_Mio_Cid_Menend_3_djvu.txt`).
  The Cid file holds both the paleographic and the critical text and
  Pidal's apparatus. A "~N" count is a count over all of these, so it shows
  that a form occurs, not how often. Accentless paleographic *oyo* is the
  preterite *oyó*, not a 1sg.
- en.wiktionary, for the Old French conjugation tables, the Old Spanish
  entries and the modern Spanish and French tables. fr.wiktionary, for the
  conjugation tables of *ouïr* and *choir* and the entry for *clamer*.
- **TLFi etymologies.** These *are* reachable now, through the JSON API
  behind the CNRTL app: `https://www.cnrtl.fr/api/word/<form>/verbe`, field
  `etymology`. The source column cites the human-facing URL
  `https://www.cnrtl.fr/etymologie/<form>`. Earlier batches said TLFi could
  not be reached.
- WP *Phonological history of French*, for the dating of en > an.
- **Not reached**: DCECH, CORDE, Pope, Penny, Lloyd, Zink, Godefroy. No
  Old Spanish conjugation tables exist on en.wiktionary for these verbs; its
  OSp entries give only the headword and sometimes the principal parts.

## The kind column, and what "analogical" means here
The `latin` column gives the etymon each form actually continues. Wherever
that is not the regular reflex of the classical form, the row is
`analogical`, and the note says what it was rebuilt on. In practice:
- **Spanish -er verbs from 3rd-conjugation -ĕre** (vender, creer, bever,
  leer, meter, saber, caer). INF, 1PL, 2PL, FUT and the -ido participle are
  all analogical: \*vendēre, \*vendēmus, \*vendētis, \*vendītum. So are the 3PL
  forms in -en (expected -unt > -on) and the weak preterites (vendió, bevió,
  leyó, metió, creyó, cayó for vendidit, bibit, lēgit, mīsit, credidit,
  cecidit). The Latin forms in -ĭmus, -ĭtis were stressed on the stem.
- **French -ūtum participles** (vendu, creü/cru, beü/bu, leü/lu, seü/su,
  cheü/chu, pleü/plu) are analogical. So are the -ui preterites built on
  them (crut, but, lut, chut for credidit, bibit, lēgit, cecidit).
- ***sapēre*, *cadēre*.** These VL conjugation shifts are shared by French
  and Spanish (PidalManual §110; TLFi *choir*: "passé à cadēre en b. lat.").
  I marked them `analogical` with the starred etymon, both in Spanish and in
  OF *savoir*/*cheoir*. *placēre* and *dormīre* are not affected.
- **OF/Fr 1PL -ons and 2PL -ez.** All 1PL rows are `analogical`, because -ons
  < \*-umus (NyropII §55). 2PL -ez is analogical outside the -āre verbs
  (NyropII §56–57: dormītis > \*dormētis > dormeiz > dormez). This is stricter
  than the pilot, which gave *chantons* no kind. If the model generates -ons
  with a morphological rule, treat these as expected rather than as misses.
- **French 1sg -s** (vends, crois, mets, sais, lis) is spelling only. The
  pronunciation continues OF *vent, croi, met, sai, li* regularly, so these
  are `inherited`. Where the sound changed by analogy, the row is
  `analogical`: *dors* (OF *dorm*), *bois* (OF *boif*), *plais* (OF *plaz*),
  *lave* (OF *lef*), *pèse* (OF *pois*), *clame* (OF *claim*).
- **A future built on a changed infinitive** is analogical: Sp *oiré* and
  *caeré* (OSp *odré*, *cadré*), Fr *croirai* and *boirai* (OF *crerai*,
  *bevrai*), *ouïrai* and *choirai*.

## Disagreements between sources
1. **OF final -t after a vowel in preterites.** Bourciez §151 Rem. I says
   the old 3sg perfects were *chanta, fu, valu, dormi*, with no t, and that
   the t was restored in spelling in Middle French. But NyropII §194–196
   and Wiktionary write *sout/sot, crut, but, lut, chut, plot*. Following the
   convention ("final -t after a vowel gone"), I wrote these without t:
   /sou, kry, by, ly, tʃy, plou/. Where the t followed a Latin consonant
   (*set* < sap(i)t, *ot* < aud(i)t, *boit*, *croit*, *chiet*, *mist*), I kept it
   (Bourciez §152: deb(e)t > *doit*, t pronounced in the Middle Ages).
2. **OF *sout* vs *sot*, *plout* vs *plot*.** Nyrop has *sout*, Wiktionary has
   *sot*. Both the vowel (/ou/ or /ɔ/) and the timing of ou > o are
   uncertain. Confidence is low.
3. **OF *cheoir* preterite.** Wiktionary lists *cheï, chaï, chut*. Nyrop §196
   gives only \*cadui > *chui*. I gave *chut*, the ancestor of the modern form,
   with low confidence and *cheï* /tʃəi/ in the spelling cell.
4. **OF *cheoir* present.** Nyrop §119.1 has *chie chies chiet cheons cheez
   chient*. Wiktionary has *chié chiez chiet ... chiéent*. I used Wiktionary's
   *chiez* (d + s > ts) and *chieent*, and noted Nyrop's forms.
5. **OF *plaisir* vs *plaire*.** Nyrop §74.2 says *plaisir* was replaced by
   *plaire* "dès le XIIe siècle". TLFi says *plaisir* was used as an infinitive
   until the 13th c., and dates *plaire* to the early 12th c. (St Brendan,
   Anglo-Norman). Both existed c.1150. I gave the regular *plaisir* and
   noted *plaire*.
6. **OF *croire* vs *creire*, *boivre* vs *beivre*, *savoir* vs *saveir*,
   *pois* vs *peis*.** These are the pilot's ei/oi question again. TLFi has
   *creire* in the Roland (ca 1100) and the Psautier de Cambridge (1st half
   of the 12th c.), and *beivre* in Wace (1160). I wrote oi as the pilot did
   (*avoir*). Wiktionary calls the ei forms archaic or northern. Since the
   dated attestations near 1150 are ei forms, ei may be the safer choice.
7. **OF *vendié* vs *vendi(t)*.** Nyrop §171–172 has *vendiet* (< \*vendēdit)
   in the Roland, Psautier d'Oxford, Benoît and others into the 13th c., but
   says the -i- forms won. I gave *vendié* (Wiktionary's form) with medium
   confidence.
8. **OF *oïr*: /oir/ or /uir/.** Wiktionary gives classical /uˈiɾ/. I wrote
   /oir/, because the pretonic o > u raising is generally put later. Medium
   confidence.
9. **OF *lire* 2pl.** Wiktionary has *lisiez*, with -iez after a palatal
   stem, and likewise *plaisiez*. Other sources have *lisez*. Confidence is
   low.
10. **OSp *oír* 2sg/3sg.** PidalManual §113.5 says *audis* gave old *odes*,
    replaced by analogical *oyes*, with y spreading from *oyo, oyendo, oyó*.
    The Cid has *oye* once. I found no date for *odes* > *oyes* and gave
    *oyes* with low confidence.
11. **OSp future of *oír* and *caer*.** The Cid has only *odredes* (14×, from
    *odir*) and *cadrán*. So I gave *odré/odrá* and *cadré/cadrá*, not
    *oiré/caeré*. PidalCid §99.
12. **OSp future of *bever*.** PidalCid §99 cites syncopated *bevrait* (Biblia)
    and unsyncopated forms beside it. No Cid form exists. I gave *bevré*
    with low confidence. *venderé*, *meteré* and *leeré* are also unattested
    by me and have low confidence. *vendré* and *metré* are possible OSp
    syncopations.
13. **OSp *creer* 1sg.** PidalManual §113.2 gives "credo, ant. creyo". I gave
    *creo* with medium confidence and noted *creyo*.
14. **OSp participles in -udo.** The Cid has *metudo, metuda* (vv. 527, 625)
    beside *metido* (4×), and *vençudo* beside *vencido* (PidalCid §97). It
    has *vendido* and *sabida(s)*. PidalManual §121.2 calls -udo "muy común en
    el siglo XIII" but soon lost. I gave the -ido forms and noted -udo.
15. **OSp strong vs weak preterites.** The Cid uses weak *metió* and *creyó*
    where other texts have *miso* and *crovo* (PidalCid §92). I followed the
    Cid. It has strong *sopo* (*sope* 2202) and *plogo* (PidalCid §93).
16. **OSp *dormir* preterite.** PidalManual's paradigm has *durmió*, with the
    u from the yod. Unraised *dormió* is also medieval, and the Cid has no
    form. Medium confidence.

## Judgement calls
- **en > an in OF.** WP dates the lowering of nasal ẽ to [æ̃] > ã to the
  11th or early 12th c. in Francien, but not in Anglo-Norman. Wiktionary
  gives *vendre* archaic /vendrə/ and classical /vandrə/. I wrote *vendre*
  /vandrə/ and *penser* /panser/. The convention leaves nasalisation unmarked
  but says nothing on vowel quality, so this choice should be confirmed.
- **OF vowel of *lef, ses, set, sevent*.** I wrote these with /e/, the
  stressed-free-a vowel the pilot wrote in -er (NyropII §25, a/e apophony:
  *lef levés ... lavons*).
- **OF *peser* /pəzer/, 1sg *pois*.** I used ə for the pretonic e, and oi in
  the stressed forms (NyropII §26.1: e/ei/oi apophony). Modern *pèse* comes
  from the unstressed stem with è (Garnier still has *je les poise*, late
  16th c.).
- **OSp /b/ vs /β/.** Per the convention, *saber, sabes, sabré, sabido* have
  /b/ (< -p-) and *sopo* keeps /p/ after au. *lavar* and *bever* have /β/
  (< -v-, -b-). Initial v- in *vender* is /β/, following Wiktionary's OSp
  IPA /βenˈdeɾ/. The pilot had no initial v- to compare.
- **OSp *plaze* vs *plaz*.** The Cid has both (*plaze* ~31, *plaz* ~12). I gave
  the full form.
- **OSp *piensa* vs *pensa*.** The Cid has *pienssan* (16×), *pienssa* and
  *penssa* (1× each). PidalManual §112 bis.4 calls *pensa* etymological and
  *piensa* analogical. I gave *piensa*. All pensare-l rows have kind
  `semi-learned`, as the brief asked, and the analogical diphthong is
  noted.
- **Learned/inherited status of the pensare doublet.** Wiktionary says OSp
  *pensar* is "semi-learned", OF *penser* is "borrowed", and *peser*/*pesar*
  are inherited. PidalManual §47 calls *pesar* the popular derivative of
  *pensare*. TLFi says only "Du lat. pensare" and gives *penser* from the
  Passion (end of the 10th c.). Since *penser* is that early and is fully
  integrated phonologically, I labelled both *penser* and *pensar*
  semi-learned, not learned.
- **clamare in French.** OF *clamer* is the inherited reflex, not a learned
  word: French keeps cl- (TLFi: Roland, ca 1100). So no \*chamer exists.
  *claim-* is only the stressed present stem (*claim, claimes, claime,
  claiment*, NyropII §24), from stressed free a before a nasal. There is no
  OF infinitive *claimer*; English *claim* was borrowed from that stem.
  Modern *clamer* continues the word, but TLFi says that by Furetière (1690)
  it was a "vieux mot de pratique", that the sense 'crier' is rare from the
  13th c. to 1675, and that it was taken up again in the 19th c. (Daudet
  1874), perhaps after Occitan *clamar*. So it is effectively a revived
  archaism. I kept it `inherited` with medium confidence, and the levelled
  *clame* is `analogical`. Spanish *llamar* is inherited (PidalManual §39).
  Learned *clamar* also exists and is frequent in Berceo (PidalCid §33), but
  this batch gives it no rows.
- **French *ouïr*.** TLFi says it was ousted by *entendre* and survives only
  in the infinitive in set phrases and in law (*ouï les témoins*). I gave
  the traditional 3rd-group paradigm from fr.wiktionary (*ois, oit, oyons,
  oyez, oient*; fut. *ouïrai*, archaic *orrai*/*oirai*) with low confidence
  for the present. A 19th–20th c. 2nd-group remake (*ouïs, ouït, ouïssons*)
  is also listed there. INF and PTCP (*ouï*) are high.
- **French *choir*.** It is defective and used mainly as INF and PTCP. The
  present (*chois, choit, choient*), the future (*choirai*, archaic
  *cherrai*) and the passé simple (*chut*) are listed but literary.
- **Spanish *llamar*.** I wrote /ʎ/ by convention, though yeísmo /ʝ/ is
  the usual pronunciation today. Modern Spanish *placer* has preterite
  *plació*, with literary *plugo*.
- **OSp *leer*.** It is not in the Cid. PidalManual §31 cites it as the
  hiatus type (*legére, leer*). I dated it c.1200 with medium confidence.
