# Limits

**Generated — do not edit.** `python3 docs/limits_build.py` writes this file and
`test/limitstablecheck.sh` fails if it drifts from `src/`.

Every compile-time cap in `src/`, what it bounds, and whether its file discloses a truncation when
it fires. A cap is a **routing decision**: it decides what an agent can and cannot find. Set one
where the pathological tail is, never near the typical case — and when it fires, say so
(`*_capped="1"` with a `*_total=`), because a silent cut reads to the caller as "none exists".

| total caps | files | caps whose file discloses | caps whose file discloses NOTHING |
| --- | --- | --- | --- |
| 205 | 81 | 99 | **106** |

Plus 7 ranking and apportionment parameters, in their own table below: they are not caps, they
are not counted as caps, and 205 + 7 is the 212 constants this generator parses out of `src/`.

## INDEXING, OUTPUT or BOUNDARY — which half of the answer a cap bounds

**INDEXING** caps bound what can EVER be found. A silent one is unrecoverable by the caller: no
flag, no budget, no second call gets the answer back, and the output reads as "none exists".
**OUTPUT** caps bound what is SHOWN from what was found; a silent one is still a defect, but a
`--detail`, a page or a follow-up call can recover the answer. The two are not the same severity
and a single table that does not distinguish them invites fixing the cheap one first.

**BOUNDARY** is the third answer and it is not a cap at all — it is the one the census kept
getting wrong. `kUnitSizeLowRiskMax = 15` decides which SIDE of a rule a unit falls on ("15 lines
or fewer is low-risk"); `kMaxNameLen = 96` decides that a 97-character backticked token is a
sentence rather than an identifier; `kMaxPartitions = 16` bounds a hand-written `--partition=N`.
None of them truncates anything, so none can be judged by `shown=`/`total=` and none should carry
a disclosure — labelling them OUTPUT would ask for a `capped="1"` that could never honestly fire.
The distinction was named in review on #108 and the rows below now carry it.

The `class` column below carries that answer where it is known. **108 of 205 caps are classified
(37 INDEXING, 36 OUTPUT, 35 BOUNDARY); the remaining 97 render `—`, which means NOT YET
CLASSIFIED — never "neither".** Classifications live in `docs/limits_classes.tsv`, a sidecar with
a known expiry:
the tag belongs on the declaration itself, and this file exists only because the round that
produced the taxonomy could not touch `src/`. `test/limitstablecheck.sh` fails if a row there
names a cap that no longer exists.

## Refuted by re-derivation — do not re-propose

A cap that shortens an answer is measured by `docs/TUNING.md`. A cap that could make an answer
WRONG needs a different instrument: recompute the value without the bound and compare. Two were
taken through it on 2026-09-10 and both came back inert, recorded here so the next reader does
not spend the afternoon again.

- **`kSliceRdMaxIter` = 64 cannot fire.** 4,528 reaching-definition fixpoints were observed and
  the maximum iteration count reached was **1**. The bound is 63 iterations above anything real.
- **The `src/ingest_metrics.h` parameter-walk depth of 12 fires 97 times and changes nothing.**
  Output is byte-identical at 12, at 64 and at 256: the frames past depth 12 carry no parameter.

The second one is the transferable lesson. "The bound trips 97 times" reads like a finding and is
not one — a fidelity cap is judged by whether re-derivation changes the ANSWER, never by whether
the bound trips. A tripping counter is a hypothesis; the re-derivation is the measurement.

## Not caps — ranking and apportionment parameters

These decide **how** something is weighted or apportioned, not **how many** of it survive, so
they are judged by a different instrument: an eval that sets the value, not a `shown=`/`total=`
pair. A value of `0.90` cannot be a row count. Each needs a `docs/EVALS.md` anchor naming the
measurement that chose it; listing them beside truncation caps invites tuning them by intuition.

The **anchor** column is read from each constant's own trailing comment. **unsourced** means the
comment cites no measurement — the value came from somewhere, but not from anything a reader can
check. All 7 read unsourced today, which is the finding, not an omission: `kSpecificMinLen` has
the widest measured blast radius of any constant in this tree (14 invocations across 9 verbs, per
`docs/TUNING.md`) and its entire stated provenance is the parenthetical `(aider's)`. Sourcing them
means editing `src/`; a cited anchor that `docs/EVALS.md` does not contain makes this generator
refuse to write, so the column cannot be satisfied by pointing at nothing.

| constant | value | site | anchor | note |
| --- | --- | --- | --- | --- |
| `kBudgetHeadroom` | `0.90` | `src/serialize.h:605` | **unsourced** | — |
| `kCeilingFirstEntryTolerance` | `1.15` | `src/serialize.h:616` | **unsourced** | — |
| `kCommonNameDefThreshold` | `5` | `src/graph.h:244` | **unsourced** | >5 defs of the same name ⇒ common (aider's) |
| `kCoreBudgetShare` | `0.34` | `src/partition.h:98` | **unsourced** | — |
| `kExemplarCcxCeilFactor` | `4` | `src/exemplar.h:58` | **unsourced** | — |
| `kSpecificMinLen` | `8` | `src/graph.h:250` | **unsourced** | ≥8 chars …  (aider's) |
| `kZoneDistanceThreshold` | `0.5` | `src/arch.h:742` | **unsourced** | \|A+I-1\| past this → classify into pain/useless |

### `src/abicheck.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMaxStructsPerRef` | `12` | 129 | OUTPUT | display cap per ref (mirrors crossref::kStrayFilesPerRef); --detail lifts it |

### `src/accessshape.h`

Discloses: `loops_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMaxLoopsModeled` | `20000` | 164 | — | — |
| `kQueryBudget` | `50000` | 155 | — | — |

### `src/atoms.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kAtomsQueryBudget` | `100000` | 78 | — | — |

### `src/binstale.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMaxTrackedFiles` | `20000` | 59 | — | — |

### `src/cachelint.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kCacheQueryBudget` | `100000` | 78 | — | — |

### `src/cli.h`

Discloses: `bridges_capped`, `files_capped`, `inc_capped`, `modules_capped`, `rows_capped`, `sibs_capped`, `syms_capped`, `tests_capped`, `unflagged_capped`, `untested_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kConnectRadiusMax` | `12` | 3093 | — | == connectcfg::kMaxRadius (static_assert at the seam in main.cpp) |
| `kIntFlagMax` | `1000000000` | 3092 | — | parsePosInt/parseNonNegInt's own overflow ceiling |
| `kPageValueMax` | `1000000000` | 591 | — | — |

### `src/cloneidiom.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kIdiomMaxCondTokens` | `8` | 81 | BOUNDARY | `( a.b < Limit::Hi )` is 7; anything longer is not a scalar threshold |
| `kIdiomMaxLabelTokens` | `6` | 82 | BOUNDARY | `case Enum::Member :` |
| `kIdiomMaxReturnTokens` | `6` | 80 | BOUNDARY | `return Enum::Member ;` is 3; a call or an expression is not a table return |

### `src/clones.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kType3MaxBucket` | `1024` | 475 | INDEXING | skip fingerprint buckets larger than this (stop-gram cut) |
| `kType3MaxTokensForLcs` | `4096` | 456 | INDEXING | cap the LCS DP dimension per body (cost guard) |

### `src/commentcoherence.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kCommentCoherenceRowCap` | `40` | 75 | — | same shape as --readability's 40 |

### `src/contextratio.h`

Discloses: `defs_capped`, `files_capped`, `syms_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kDefsPerNameCap` | `8` | 94 | — | — |
| `kFileRowCap` | `40` | 89 | — | — |
| `kSymbolRowCap` | `40` | 88 | — | — |

### `src/crossref.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMaxGitWorkers` | `12` | 802 | — | matches the ingest pool's measured ~12-way; these are |
| `kMaxRefs` | `512` | 130 | INDEXING | refusal bound — a sweep, not a fork-network crawl |
| `kWhereisHits` | `60` | 135 | OUTPUT | — |

### `src/darkflags.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMaxAliasDepth` | `8` | 859 | INDEXING | — |
| `kMaxEnvNameLen` | `128` | 58 | BOUNDARY | longest plausible environment-variable name |
| `kMaxSitesShown` | `8` | 57 | OUTPUT | per gate, per list; the rest are counted in a <more/> |

### `src/didyoumean.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMaxEditDistance` | `3` | 155 | BOUNDARY | same bandwidth cutoff as didYouMean |
| `kMaxEditDistance` | `3` | 205 | BOUNDARY | bandwidth cutoff (§P12.1): beyond this a "hint" is noise, not help |

### `src/dmm.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kUnitComplexityLowRiskMax` | `5` | 91 | BOUNDARY | cyclomatic complexity |
| `kUnitInterfacingLowRiskMax` | `2` | 92 | BOUNDARY | parameters |
| `kUnitSizeLowRiskMax` | `15` | 90 | BOUNDARY | lines |

### `src/docdrift.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMaxAnchorsShown` | `12` | 130 | OUTPUT | drifted anchors printed per doc; detail lifts the cap |
| `kMaxClaimedLine` | `200000` | 138 | BOUNDARY | past this a "line number" is a hostile-input example, not a claim |
| `kMaxDecDigits` | `10` | 134 | BOUNDARY | overflow guard on a doc/code integer literal |
| `kMaxExtLen` | `6` | 136 | BOUNDARY | "cpp", "swift", "metal" — longer is not an extension |
| `kMaxFrontMatter` | `12` | 150 | — | — |
| `kMaxHexDigits` | `15` | 135 | BOUNDARY | …hex fits 15 nibbles in 64 bits with room to spare |
| `kMaxNameLen` | `96` | 133 | BOUNDARY | past this it is a sentence, not an identifier |
| `kMinMentionLen` | `4` | 131 | BOUNDARY | a backticked name shorter than this is prose, not code |
| `kMinValueNameLen` | `3` | 132 | BOUNDARY | …and the bar for a `= N` / `[N]` subject name |

### `src/editcheck.h`

Discloses: `unflagged_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kEditCheckSpellingsShown` | `6` | 154 | OUTPUT | — |

### `src/editpreview.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kPreviewOverwriteBudgetBytes` | `4096` | 283 | — | — |

### `src/ensemble.h`

Discloses: `files_capped`, `findings_capped`, `syms_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kEnsembleFileRowCap` | `20` | 108 | — | — |
| `kEnsembleSymbolRowCap` | `40` | 107 | — | — |
| `kOrdinalWindowCap` | `40` | 112 | — | — |

### `src/eval.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMaxSample` | `80` | 275 | INDEXING | — |
| `kMaxScored` | `4000` | 697 | INDEXING | — |

### `src/expand.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kExpandMaxPer` | `8` | 37 | OUTPUT | — |
| `kExpandMaxSeeds` | `8` | 36 | OUTPUT | out-of-range env means OFF, never a clamp-and-guess |

### `src/fieldaffinity.h`

Discloses: `aggs_capped`, `as_loops_capped`, `as_query_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMaxAggsModeled` | `8000` | 145 | INDEXING | refusal bound on the whole-repo modelling pass |
| `kMaxFieldsShown` | `32` | 144 | OUTPUT | per struct (touched fields only) |
| `kMaxFnsShown` | `8` | 143 | OUTPUT | per struct |
| `kMaxPairsShown` | `12` | 142 | OUTPUT | per struct |
| `kMaxScopeChars` | `120` | 146 | OUTPUT | displayed prefix of a PROFILE_SCOPE description |
| `kMaxStructsShown` | `20` | 141 | OUTPUT | whole-repo form: the ranked head, `capped="1"` past it |

### `src/filepool.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kPoolMaxTopK` | `32` | 29 | — | env values outside range mean OFF, never a clamp-and-guess |

### `src/flipimpact.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMaxBindings` | `32` | 93 | INDEXING | value-style constants tracked — bounds pass B's needle count |
| `kMaxChainDepth` | `8` | 92 | INDEXING | alias-chain depth cap (mirrors darkflags::kMaxAliasDepth) |
| `kMaxFamily` | `64` | 91 | INDEXING | gates one flip may light — an alias fan-out past this is a table, not a switch |
| `kMaxFlipRows` | `25` | 94 | OUTPUT | per emitted list; --detail lifts every cap |
| `kMaxNearMisses` | `5` | 95 | OUTPUT | "did you mean" suggestions on an unknown gate name |

### `src/gitmine.h`

Discloses: `coboost_commits_capped`, `coboost_partners_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kCoBoostMaxFilesPerCommit` | `30` | 2836 | INDEXING | same bulk-commit cap as the other co-change miners here |
| `kCoBoostMaxPartnerFiles` | `8` | 2839 | INDEXING | strongest partners only, by (deg desc, path asc) |
| `kCoBoostMaxSymbolsPerFile` | `3` | 2840 | INDEXING | per partner file: its top-3 symbols by (lens score desc, id asc) |

### `src/gitoracle.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMaxNameLen` | `96` | 96 | BOUNDARY | past this it is a minified blob, not an identifier |
| `kMaxNamesTracked` | `2000000` | 99 | INDEXING | map bound; 44,904 on the deepest repo measured |
| `kMaxProbeCommits` | `40000` | 97 | INDEXING | walk bound — past it, misses are "unknown", never "never" |
| `kMinNameLen` | `4` | 95 | BOUNDARY | — |

### `src/graph.h`

Discloses: `importers_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kChaConeCap` | `4096` | 465 | INDEXING | per-walk discovery cap, unchanged from the per-call walk |
| `kMaxEdges` | `256` | 5385 | — | total emitted edge cap |
| `kMaxNodes` | `96` | 5384 | — | total emitted node cap (§3 size caps) |
| `kMaxRadius` | `12` | 5387 | — | — |
| `kMaxTerminals` | `16` | 5383 | — | >16 is the CALLER's usage error; the core CLAMPS (never VERIFYs on hostile input) |
| `kMemberSpellingsShown` | `6` | 4325 | OUTPUT | — |

### `src/handoff.h`

Discloses: `syms_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kHandoffCochangeRows` | `8` | 43 | OUTPUT | heuristic co-change rows shown |
| `kHandoffDocRows` | `4` | 41 | OUTPUT | heuristic doc pointers shown |
| `kHandoffNoteRows` | `8` | 42 | OUTPUT | heuristic note rows shown |
| `kHandoffSymbolsPerFile` | `6` | 50 | OUTPUT | — |

### `src/infra/blanktext.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kBlankSpellingMaxCodePoints` | `8` | 215 | — | — |

### `src/infra/profilePmc.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMaxEvents` | `8` | 62 | — | — |

### `src/infra/sortutil.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kRadixThreshold` | `128` | 194 | BOUNDARY | — |
| `kRadixThreshold` | `2048` | 99 | BOUNDARY | — |
| `kRadixThreshold` | `2048` | 224 | BOUNDARY | — |

### `src/ingest.h`

Discloses: `ellipsis_capped`, `hits_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kBinarySniffCap` | `4096` | 207 | — | NUL-byte sniff window |
| `kMaxSkipRowsPerClass` | `500` | 125 | OUTPUT | — |
| `kUnreachableMaxHits` | `5000` | 414 | — | — |

### `src/ingest_astquery.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMaxEditDistance` | `3` | 377 | BOUNDARY | same bandwidth as didYouMean()'s symbol-name cutoff |

### `src/ingest_model.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kRadixThreshold` | `64` | 465 | BOUNDARY | — |

### `src/ingest_names.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMaxQualifierHops` | `32` | 219 | INDEXING | `a::b::c::…` past 32 segments is not written C++ |

### `src/ingest_parsepool.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kCapPerThread` | `256` | 92 | — | — |
| `kMaxPendingParsedFiles` | `4` | 286 | — | — |

### `src/ingest_relations.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMaxImportContainerDepth` | `256` | 1547 | INDEXING | — |

### `src/ingest_sidecap.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kSideDepthStd` | `256` | 1150 | INDEXING | FFI / routes / bindings — their own guard |
| `kSideDepthUses` | `512` | 1151 | INDEXING | value-uses — twice the others, as it always was |

### `src/landingplan.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMaxPlanScout` | `12` | 68 | OUTPUT | — |

### `src/lanes.h`

Discloses: `blast_capped`, `tests_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMaxBlastFiles` | `40` | 120 | — | blast-radius file rows per lane; total + capped always reported |
| `kMaxTestRows` | `40` | 121 | — | tests_to_run rows per lane; same "never drop without a number" |

### `src/layout.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMaxAssertChars` | `220` | 85 | OUTPUT | the displayed prefix of a static_assert's text |
| `kMaxDefsShown` | `24` | 87 | BOUNDARY | a name defined more often than this is a generic, not a mirror |
| `kMaxMacroDepth` | `4` | 83 | INDEXING | object-like macro expansion depth for a type name |
| `kMaxNestDepth` | `8` | 82 | INDEXING | nested-aggregate resolution depth (a cycle stops here) |

### `src/lexical.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMaxAnchorDefs` | `3` | 1787 | — | — |
| `kMaxIdentifierLookupWords` | `2` | 1936 | — | — |
| `kMaxShown` | `4` | 1608 | OUTPUT | — |

### `src/lintcatalog.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMaxEditDistance` | `3` | 341 | BOUNDARY | — |

### `src/lintrules.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kLintMaxPerRule` | `5000` | 821 | — | — |

### `src/main.cpp`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kRecentRows` | `40` | 982 | — | F3: ~45 B a row; the file-level answer, not the file list |

### `src/mcpedit.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMaxEditDistance` | `3` | 206 | BOUNDARY | the read verbs' bandwidth (didyoumean.h::didYouMean) |
| `kReceiptRegionBudgetBytes` | `2048` | 891 | — | — |

### `src/mcpjson.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kFrameEchoCaptureBytes` | `240` | 529 | — | > mcprefusal.h's kMcpEchoMaxBytes, so the cap still shows |

### `src/mcprefusal.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMaxEditDistance` | `3` | 926 | BOUNDARY | — |
| `kMaxEditDistance` | `3` | 1116 | BOUNDARY | same bandwidth cutoff nearestName searches within |
| `kMcpEchoMaxBytes` | `160` | 363 | — | — |

### `src/mcpverbs.h`

Discloses: `coboost_commits_capped`, `hits_capped`, `unindexed_candidates_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kBatchCap` | `16` | 4218 | — | max sub-queries processed per batch; excess is REPORTED, never silently dropped |
| `kMcpPageValueMax` | `1000000000` | 306 | — | == cli.h's kPageValueMax |
| `kMcpRecallTopKMax` | `1000` | 312 | — | — |
| `kOtherDefCap` | `4` | 3953 | OUTPUT | disclosure, not a listing — cap the tail |
| `kRowCap` | `100` | 889 | — | — |

### `src/mention.h`

Discloses: `doc_mentions_capped`, `mention_files_capped`, `mention_syms_capped`, `mention_tokens_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kDocMentionMaxAnchors` | `8` | 759 | INDEXING | consult only the current top-N anchors |
| `kDocMentionMaxDocsPerAnchor` | `2` | 760 | INDEXING | strongest-anchor-first, capped per anchor |
| `kDocMentionMaxDocsTotal` | `6` | 761 | INDEXING | global cap — bounds token cost regardless of fan-out |
| `kMentionMaxDirectSymbols` | `8` | 160 | INDEXING | directly-named (Scope.name / `name`) symbols, id asc |
| `kMentionMaxFiles` | `4` | 158 | INDEXING | strongest evidence only: files named first in the text |
| `kMentionMaxRawTokens` | `16` | 157 | INDEXING | extraction cap: first N candidate mention tokens, text order |
| `kMentionMaxSymbolsPerFile` | `3` | 159 | INDEXING | per mentioned file: its top symbols by (lens score desc, id asc) |

### `src/model.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMaxWorkspaceRoots` | `16` | 938 | — | — |

### `src/namingconsistency.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kRowCap` | `40` | 67 | — | same shape as --hotspots/--readability's 40 |

### `src/naminglens.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kConfusableGroupMax` | `512` | 425 | — | beyond this many co-visible names the O(n²) pair scan |

### `src/nextverb.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kNextAttrMaxBytes` | `120` | 26 | — | — |

### `src/nonlocalstate.h`

Discloses: `cells_capped`, `decls_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kCellsPerRowCap` | `12` | 116 | — | — |
| `kDeclMatchBudget` | `40000` | 124 | — | — |
| `kMaxCells` | `2048` | 120 | — | — |
| `kRowCap` | `40` | 88 | — | — |

### `src/packtask.h`

Discloses: `mention_syms_capped`, `ranking_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kOverCeilingKeyBytes` | `22` | 1653 | — | `,"over_ceiling":true` + the closing brace |
| `kPackTaskRankTopN` | `12` | 89 | — | ranking = the top-12 head, not the full 40 — leaves budget for the later sections |

### `src/pageview.h`

Discloses: `count_capped`, `findings_capped`, `hits_capped`, `importers_capped`, `modules_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kCallHierarchyRowCap` | `40` | 164 | — | — |
| `kCochangePartnerCap` | `30` | 170 | — | — |
| `kExternalSurfaceRowCap` | `100` | 186 | — | names, by ref count (≈ 5.2 KB on this repo) |
| `kImportReachRowCap` | `40` | 179 | — | — |
| `kPageDisclosureCap` | `224` | 366 | — | — |
| `kTreeRowCap` | `80` | 184 | — | files, by best symbol's rank: 80 rows ≈ 11.5 KB on this repo (100 = 14.3 KB) |
| `kUseSiteRowCap` | `100` | 165 | — | — |
| `kZoomTopModuleCap` | `40` | 185 | — | top-level modules, size desc (their children ride along: levels_shown=2) |

### `src/partition.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMaxPartitions` | `16` | 94 | BOUNDARY | — |

### `src/pattern.h`

Discloses: `hits_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMaxHits` | `5000` | 81 | — | same per-verb budget --match spends |
| `kMaxMetavars` | `32` | 79 | — | bindings live in a fixed-size env on the stack |
| `kMaxPatternBytes` | `4096` | 78 | — | a pattern is a code SHAPE, not a file |

### `src/prcontext.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kPrDefaultBudgetTokens` | `8000` | 452 | — | — |

### `src/quality.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMaxCacheBlobAgeDays` | `30.0` | 1850 | BOUNDARY | — |
| `kMaxCacheBlobCount` | `4096` | 1852 | BOUNDARY | bound every future hygiene scan |
| `kMaxEditLockAgeDays` | `1.0` | 1862 | BOUNDARY | — |
| `kRenameMaxChain` | `8` | 1038 | INDEXING | a→b→c… chain depth followed from one current path (disclosed) |
| `kRenameMaxPairs` | `4000` | 1037 | INDEXING | hard cap on recorded pairs (disclosed when hit) |

### `src/qualitypanel.h`

Discloses: `findings_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kPanelRowCap` | `40` | 145 | — | — |

### `src/readability.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kReadabilityRowCap` | `40` | 61 | — | — |

### `src/recall.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kDefaultRecallMaxTokens` | `8000` | 311 | — | — |

### `src/redact.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kGenericMinRunLength` | `32` | 296 | — | — |

### `src/renamemine.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMaxCandidates` | `200000` | 105 | INDEXING | vote-map bound; 560 on the deepest history measured |
| `kMaxHunkSide` | `24` | 103 | INDEXING | per-side cap on the O(n²) line pairing; over-wide hunks are dropped + counted |
| `kMaxIdentLen` | `96` | 102 | BOUNDARY | past this it is a minified blob, not an identifier |
| `kMaxIdentsPerLine` | `256` | 106 | INDEXING | a line with more tokens than this is not hand-written code |
| `kMaxLineLen` | `2000` | 104 | BOUNDARY | a line this long is generated/vendored, not a rename site |
| `kMinIdentLen` | `2` | 101 | BOUNDARY | — |

### `src/resolve.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kFieldWalkCap` | `16` | 2312 | INDEXING | total visited names — bounds depth and width together |

### `src/search.h`

Discloses: `hits_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kGrepCollectionBudget` | `4000000` | 1445 | — | — |
| `kGrepMatchedLineMaxBytes` | `512` | 941 | — | — |
| `kGrepTierFileBudget` | `128` | 2072 | — | hit files classified per call |
| `kMaxAffixSet` | `8` | 195 | — | cap on prefix/suffix set sizes |
| `kMaxExactLen` | `24` | 194 | — | beyond this exact-string length, give up exactness (⊤) |
| `kMaxExactSet` | `8` | 193 | — | beyond this many exact strings, give up exactness (⊤) |

### `src/selectorrefuse.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kSelectorFilesShown` | `6` | 42 | OUTPUT | — |

### `src/serialize.h`

Discloses: `calls_capped`, `inc_capped`, `sibs_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kCap` | `65536` | 420 | — | — |
| `kForAnchorBodyBudgetBytes` | `22800` | 794 | — | — |
| `kForAutoBodyBudgetBytes` | `6000` | 760 | — | — |
| `kForCapTailSigBytes` | `96` | 727 | — | — |
| `kForCompactSurfaceBudgetBytes` | `1000` | 970 | — | — |
| `kForFileTailShownCap` | `24` | 815 | — | — |
| `kForLensDefaultTopN` | `40` | 740 | — | — |
| `kForPayloadBudgetBytes` | `7500` | 726 | — | — |
| `kMaxExpandIncludes` | `24` | 4584 | — | inc= cap |
| `kMaxExpandSibs` | `100` | 4575 | — | sibs= cap — a BLOW-UP GUARD, set above the tail, not a trim of the |
| `kMaxSig` | `240` | 2707 | OUTPUT | — |
| `kWithGraphNodeCap` | `8` | 5642 | — | — |

### `src/siblift.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kSibliftMaxSeed` | `4` | 25 | OUTPUT | env values outside [1, kSibliftMax*] mean OFF, never a clamp-and-guess |
| `kSibliftMaxSib` | `4` | 26 | OUTPUT | — |

### `src/situ.h`

Discloses: `tests_capped`, `untested_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMaxUntestedRows` | `25` | 939 | — | — |
| `kSituBlastFilesShown` | `8` | 348 | OUTPUT | section [1] — blast-radius file rows |
| `kSituPartnerFileRowsShown` | `4` | 351 | — | section [1] — decl/def partner rows |
| `kSituPartnerRowsShown` | `8` | 350 | — | section [3] — co-change partner rows |
| `kSituTestRowsShown` | `25` | 349 | — | section [2] — tests-to-run rows |

### `src/skillscan.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kSkillScanFindingCap` | `200` | 843 | INDEXING | generous for one file or a small dir; caps a pathological --scan-skills sweep |

### `src/slice.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kSliceFlowDefaultDepth` | `8` | 2094 | — | the disclosed default bound (depth= always states it) |
| `kSliceFlowDepthMax` | `32` | 2098 | — | — |
| `kSliceFlowDepthMin` | `1` | 2097 | — | — |
| `kSliceRdMaxIter` | `64` | 1205 | OUTPUT | — |

### `src/slicediff.h`

Discloses: `diff_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMaxDiffRows` | `2000` | 71 | — | — |
| `kMaxRenameHops` | `8` | 75 | — | — |

### `src/taskroute.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMinWeakSymbolLen` | `5` | 151 | — | — |

### `src/tracelocus.h`

Discloses: `name_ladder_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMeasuredDigitsPricedWidth` | `6` | 873 | OUTPUT | — |
| `kNameCandidateCap` | `8` | 141 | OUTPUT | — |
| `kTestHopBasenameRowCap` | `3` | 424 | OUTPUT | — |
| `kTestHopCalleeRowCap` | `5` | 423 | OUTPUT | — |

### `src/verbs_change.h`

Discloses: `seed_files_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kRunTraceRelevantLinesCap` | `40` | 696 | — | <lines view="relevant"> cap (first/last half split past it) |

### `src/verbs_doctor.h`

Discloses: **none**

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kShown` | `8` | 829 | OUTPUT | — |

### `src/verbs_for.h`

Discloses: `coboost_commits_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kJsonEnvelopeDigitsMax` | `10` | 911 | — | — |

### `src/verbs_lint.h`

Discloses: `count_capped`, `ellipsis_capped`, `findings_capped`, `hits_capped`, `rows_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kMatchMaxHits` | `5000` | 1296 | INDEXING | astQuery's per-spec budget, named not implied |

### `src/verbs_navigate.h`

Discloses: `importers_capped`

| constant | value | line | class | note |
| --- | --- | --- | --- | --- |
| `kEvidenceCap` | `20` | 1339 | OUTPUT | — |

