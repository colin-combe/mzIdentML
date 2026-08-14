# CV mapping rules: validator XML vs. specification document

**Date:** 2026-08-08 · **Repo:** HUPO-PSI/mzIdentML (branch `antora`)

## Verdict

Confirmed — the two have diverged substantially, and **the validator XML is the more complete and current of the two for everything up to mzIdentML 1.2.0**. The spec document's per-element *cvParam Mapping Rules* blocks look like a snapshot taken years ago that was never re-synchronised.

But it is not a one-way drift. There are also a handful of places where the **spec doc is ahead** — it documents 1.3.0 / crosslinking-era terms that were never added to the validator mapping file. So the honest summary is:

> The mapping file is authoritative for 1.1.0/1.2.0 semantics; the spec doc has picked up some 1.3.0 content that the mapping file is missing. Neither is currently a complete description of 1.3.0.

The spec document itself says the mapping file governs (`mzidentml.adoc`, *Validation of controlled vocabulary terms*): *"The correct usage of controlled vocabulary terms within mzIdentML is governed by the use of a mapping file …"* — so where the two disagree, the mapping file wins by the spec's own rule.

## Sources compared

| | |
|---|---|
| Validator rules | `validator/resources/mzIdentML-mapping_1.2.0.xml` — 55 active `CvMappingRule`s over 39 distinct scope paths, plus 2 commented-out rules. Last substantive commit **July 2019**. |
| Spec document | `specification_document/specdoc1_3/asciidoc/model-in-xml-schema.adoc` — 33 *cvParam Mapping Rules* headings, 38 `Path …` blocks, 81 requirement statements. |

`validator/resources/` and `validator/trunk/src/main/resources/` are byte-identical, as is the copy inside `mzIdentMLValidator_GUI_v1.4.35-SNAPSHOT.zip`, so there is only one mapping file to worry about.

**Coverage overlap:** 36 paths appear in both; 3 paths have rules in the mapping file but *no* rules block in the spec; 2 paths have a rules block in the spec with no counterpart rule in the mapping file.

## The structural problem first

**There is no `mzIdentML-mapping_1.3.0.xml`.** The repo ships mapping files for 1.1.0 and 1.2.0 only. The spec document being maintained is `specdoc1_3`, and the schema `mzIdentML1.3.0.xsd` exists. (Element names in 1.3.0 are identical to 1.2.0, so the 1.2.0 paths all remain valid — a 1.3.0 mapping file could start as a copy.) Until that file exists, any 1.3.0-specific rule written into the spec doc is unenforceable and untested.

Two secondary points that follow from the same neglect:

- The bundled `psi-ms.obo` is **data-version 4.1.28, dated 2019-07-16**. `MS:1003392` (*search modification id*), which the spec doc already cites, does not exist in it.
- `crosslinking_ext.adoc` contains **zero** *cvParam Mapping Rules* blocks, even though the mapping file carries XLMOD rules on `<SearchModification>` and `<Modification>`.

---

## A. Terms in the validator that the spec doc omits

These are straightforward additions to the spec doc. Grouped by the element section that needs editing.

### `<Person>` / `<Organization>` (AuditCollection)

The mapping file's SHOULD lists were extended in 2019 (commit `5f328c4`) and the spec doc never followed.

| Element | Missing from spec (all SHOULD) |
|---|---|
| `<Person>` | `MS:1000590` contact affiliation · `MS:1001755` contact phone number · `MS:1001756` contact fax number · `MS:1001757` contact toll-free phone number |
| `<Organization>` | `MS:1001755` contact phone number · `MS:1001756` contact fax number · `MS:1001757` contact toll-free phone number |

### `<AdditionalSearchParams>`

Spec lists 4 of the 7 terms in `AdditionalSearchParams_may_rule`, and none of the five single-term feature-flag rules.

Missing (all MAY):
`MS:1000044` dissociation method · `MS:1002473` ion series considered in search · `MS:1002658` identification parameter · `MS:1002490` peptide-level scoring · `MS:1002491` modification localization scoring · `MS:1002494` cross-linking search · `MS:1002635` proteogenomics search

The last four are the feature flags for exactly the workflows `mzidentml.adoc` §*Comments on Specific use cases* describes at length (peptide-level scores, mod localisation, crosslinking, proteogenomics) — so the prose and the element reference are out of step with each other as well.

### `<Threshold>` — the worst case

Both threshold paths are badly out of date. The mapping file has a **MUST** rule on each; **the spec doc has no MUST statement at all for either**, only MAY.

`/…/SpectrumIdentificationProtocol/Threshold` — missing MUST (OR-combination) over:
`MS:1001153` · `MS:1001302` · `MS:1001494` · `MS:1002363` search engine specific score for proteins · `MS:1002484` peptide-level statistical threshold · `MS:1002573` spectrum identification statistical threshold · `MS:1002701` PSM-level result list statistic · `MS:1002703` peptide sequence-level result list statistic
— and missing MAY: `MS:1001060` · `MS:1002347` · `MS:1002358` · `MS:1002484` · `MS:1002555`

`/…/ProteinDetectionProtocol/Threshold` — missing MUST (OR-combination) over:
`MS:1001153` · `MS:1001302` · `MS:1001494` · `MS:1002572` protein detection statistical threshold · `MS:1002706` protein group-level result list statistic
— and missing MAY: `MS:1001494` · `MS:1002485` · `MS:1002555` · `MS:1002701` · `MS:1002706`

### `<SearchModification>`

The spec doc renders `MS:1001460` (*unknown modification*) as the sole MUST and lists everything else as MAY. In the mapping file the MUST is an **OR over seven terms** — i.e. a `<SearchModification>` must carry *one of* unknown modification / cross-link donor / cross-link acceptor / a UNIMOD child / a MOD child / an XLMOD:00002 child / an XLMOD:00004 child. As written, the spec doc says every SearchModification must be an unknown modification, which is wrong and would fail every normal file.

Also missing from the MAY list: `MS:1001189` modification specificity peptide N-term · `MS:1001190` peptide C-term · `MS:1002057` protein N-term · `MS:1002058` protein C-term.

### `<SearchType>`

Spec says "MUST supply a *child* term of `MS:1001080` (search type)". The mapping file instead enumerates six specific terms with `allowChildren="false"`:
`MS:1001010` de novo search · `MS:1001031` spectral library search · `MS:1001081` pmf search · `MS:1001082` tag search · `MS:1001083` ms-ms search · `MS:1001584` combined pmf + ms-ms search

These are not equivalent — the validator restricts to the enumerated six, the spec permits any descendant of `MS:1001080`. Two further MAY rules (`DenovoSearchType_may_rule`, `SpectralLibrarySearchType_may_rule`) are absent from the spec entirely.

### `<Modification>` — no rules block at all

`/MzIdentML/SequenceCollection/Peptide/Modification` has **two** rules in the mapping file (`PeptideModification_must_rule`, `CrosslinkingPeptideModification_may_rule`) and **no** *cvParam Mapping Rules* block in the spec doc. Both rules cover the same 8 terms:

`MS:1002509` cross-link donor · `MS:1002510` cross-link acceptor · `UNIMOD:0` (children) · `MOD:00000` (children) · `MS:1001471` peptide modification details (children) · `XLMOD:00005` homofunctional cross-linker (children) · `XLMOD:00006` heterofunctional cross-linker (children) · `XLMOD:00008` zero-length cross-linker (children)

This is the single biggest gap — it's the crosslinking core, and it's undocumented in the element reference.

### `<SpectrumIdentificationList>` — no rules block at all

Mapping has `SpectrumIdentificationList_may_rule`: MAY a child of `MS:1001184` (search statistics). Spec has no block.

### `<ProteinDetectionHypothesis>` — wrong path, and incomplete

The spec's path reads `/MzIdentML/DataCollection/AnalysisData/ProteinDetectionList/ProteinAmbiguityGroup/**ProteinDetection**` — truncated; it should be `ProteinDetectionHypothesis`. (`model-in-xml-schema.adoc:2607`)

Missing from the MAY list: `MS:1001085` protein-level identification attribute · `MS:1001143` PSM-level search engine specific statistic · `MS:1001805` quantification datatype.
Missing entirely: the **MUST** rule requiring a child of `MS:1001101` (protein group or subset relationship).

The spec lists `MS:1002401` / `MS:1002402` / `MS:1002403` as separate rule statements; these are all children of `MS:1001101` so they are covered by the MUST rule and are better presented as `e.g.:` examples under it. That also makes the "every PDH MUST be leading or non-leading" requirement in `mzidentml.adoc` §*Protein grouping encoding* consistent with the element reference, which it currently is not.

### `<SpectrumIdentificationItem>`

Missing MAY: `MS:1000894` retention time · `MS:1002484` peptide-level statistical threshold.
Missing MUST (two identical rules, `PeptideLevelStatsSpectrumIdentificationItem_may_rule` and `ModLocalizationSpectrumIdentificationItem_must_rule`, both OR-combination over):
`MS:1001143` · `MS:1001968` PTM localization PSM-level statistic · `MS:1002538` PTM localization confidence metric · `MS:1002549` PTM localization distinct peptide-level statistic · `MS:1002555` PTM localization score threshold

### Remaining single-term omissions

| Element | Missing |
|---|---|
| `<DBSequence>` | MAY `MS:1002636` proteogenomics attribute (children); MAY `MS:1001088` protein description (separate AND rule) |
| `<SpectrumIdentificationResult>` | MAY `MS:1000894` retention time |
| `<IonType>` | MAY `MS:1000336` neutral loss |
| `<SpectrumIDFormat>` | MUST `MS:1002646` native spectrum identifier format, combined spectra |
| `<ProteinDetectionList>` | MAY `MS:1002405` protein group-level result list attribute · `MS:1002704` protein-level result list attribute |
| `<ProteinAmbiguityGroup>` | MAY `MS:1002346` protein group-level identification attribute · `MS:1002470` / `MS:1002471` / `MS:1002542` (PeptideShaker) · `MS:1002698` protein cluster identification attribute |

---

## B. Rules in the spec doc with no counterpart in the validator

These need a decision each: either add the rule to the mapping file, or drop it from the spec.

| Element | Spec-only statement | Assessment |
|---|---|---|
| `<SearchModification>` | MAY `MS:1003392` search modification id | **Genuinely newer.** 1.3.0 crosslinking feature, described in `crosslinking_ext.adoc:335`. Should be **added to the mapping file** (along with `MS:1003393` *search modification id ref* on `<Modification>`, which neither file has as a rule). |
| `<Peptide>` | MAY `MS:1001355` peptide descriptions | The mapping file's `Peptide_may_rule` is **commented out**. Either uncomment it or delete the spec block; leaving it as-is is the worst option. |
| `<AnalysisParams>` (PDP) | MAY child of `MS:1001194` quality estimation with decoy database | `MS:1001194` is a leaf boolean with no children — "child term of" is wrong regardless. Probably should be a `useTerm` rule in the mapping file, or dropped. |
| `<Threshold>` (SIP) | MAY `MS:1001448` pep:FDR threshold | Plausible; not in the mapping rule. Decide and align. |
| `<Threshold>` (PDP) | MAY `MS:1001447` prot:FDR threshold; MAY child of `MS:1002482` statistical threshold; MAY child of `MS:1002664` interaction score derived from cross-linking | `MS:1002664` on the *protocol* threshold looks like a copy-paste from the PDH rule and is likely wrong. The other two are plausible additions to the mapping file. |
| `<ProteinDetectionHypothesis>` | `MS:1002401` / `MS:1002402` / `MS:1002403` as standalone MAY statements | Redundant — covered by the `MS:1001101` MUST rule. Demote to examples. |

---

## C. Systemic / presentational issues

**1. OR / XOR combination logic is not rendered.** The spec doc joins requirement statements with ` +` line continuations, which reads as *all of these apply*. But the mapping file's `cvTermsCombinationLogic` is `OR` for most multi-term rules and `XOR` for one. The distinction matters:

| Path | Logic | Spec currently implies |
|---|---|---|
| `SpectraData/SpectrumIDFormat` | **XOR** — exactly one of `MS:1000767` / `MS:1001529` / `MS:1002646` | both listed terms required |
| `FragmentationTable/Measure` | **OR** over `MS:1001225` / `MS:1001226` / `MS:1001227` | all three required |
| `DatabaseTranslation/TranslationTable` | **OR** over `MS:1001025` / `MS:1001410` / `MS:1001423` | all three required |
| `SearchModification`, `SearchType`, both `Threshold`s | **OR** | see §A |
| `ParentTolerance`, `FragmentTolerance` | **AND** — genuinely both required | correct as written |

Recommendation: adopt an explicit phrasing convention, e.g. *"MUST supply **at least one** of the following …"* for OR, *"MUST supply **exactly one** of …"* for XOR, and keep the current joined form only for AND.

**2. Stale term names.** Names quoted in the spec no longer match `psi-ms.obo`:

| Accession | Current CV name | Spec doc says |
|---|---|---|
| `MS:1001221` | product ion attribute | fragmentation information *(this is the term's **definition** text, not its name)* |
| `MS:1001116` | single protein identification statistic | single protein result details |
| `MS:1002509` / `MS:1002510` | cross-link donor / cross-link acceptor | crosslink donor / crosslink acceptor |
| `MS:1002664` | interaction score derived from cross-linking | inconsistent — "cross-linking" in `<ProteinDetectionHypothesis>`, "crosslinking" in `<Threshold>` |

**3. Path casing — do *not* "fix" this.** The mapping file uses object-model casing for the leading character of many steps (`/AuditCollection/person`, `/…/contactRole/role`, `/…/sourceFile/fileFormat`, `/…/spectrumIdentificationResult/…`) because psi-tools resolves paths against the jmzIdentML object model. The spec doc's CamelCase paths are the correct *XML* paths and should stay as they are. (The mapping file is not even self-consistent here: `/…/databaseTranslation/TranslationTable` mixes both conventions.)

**4. Dead OLS URLs.** The spec's term links point at `http://www.ebi.ac.uk/ols/beta/ontologies/…`, an OLS beta host that no longer resolves. A few entries use the newer `https://www.ebi.ac.uk/ols/ontologies/…` form. Worth a bulk rewrite to current OLS4 URLs while the file is being edited anyway.

**5. Malformed markup, spotted in passing.**
- `model-in-xml-schema.adoc:3071` — `MS:1003392` has underline markup but no link, unlike its neighbours.
- `model-in-xml-schema.adoc:3999` — `e.g.: MS:1001009 (SEQUEST:DescriptionLines` — unclosed parenthesis.
- The literal `MS:1001302[et al.]` / `MS:1001153[et al.]` / `MS:1001045[et al.]` / `MS:1001512[et al.]` lines render as a bare link labelled "et al." Intent is clearly "and others"; worth making that explicit text.

---

## Recommended order of work

1. **Create `validator/resources/mzIdentML-mapping_1.3.0.xml`** as a copy of the 1.2.0 file. Without it there is no target to synchronise the 1.3.0 spec doc against. Add the 1.3.0 crosslinking rules (`MS:1003392` on `<SearchModification>`, `MS:1003393` on `<Modification>`) there.
2. **Refresh `psi-ms.obo`** (currently 4.1.28 / July 2019) so `MS:1003392` and other post-2019 terms resolve.
3. **Resolve the §B decisions** — for each spec-only rule, add to the mapping file or delete from the spec. These are the only items requiring judgement; everything else is mechanical.
4. **Apply the §A additions** to `model-in-xml-schema.adoc`. Highest value first: `<Modification>` (missing entirely), both `<Threshold>`s (missing MUST rules), `<SearchModification>` (MUST is misleading as written), `<AdditionalSearchParams>` feature flags.
5. **Fix the §C issues** — the `ProteinDetection` → `ProteinDetectionHypothesis` path typo, stale term names, OR/XOR phrasing convention, OLS URLs.
6. **Automate it.** These blocks are pure derived content. Generating the *cvParam Mapping Rules* sections from the mapping file at build time (the repo already has `gen-docs.sh` and `compare_adoc_specs.py` doing comparable work) would prevent this drift recurring, and would make the OR/XOR logic render correctly by construction.
