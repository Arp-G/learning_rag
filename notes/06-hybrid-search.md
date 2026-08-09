# Hybrid Search — combining keyword + semantic

> **TL;DR** — BM25 and semantic search fail on *different* queries, so run **both**
> and fuse their rankings. Two ways: **RRF** combines *ranks* (robust, one knob `k`,
> ignores score scales) and **weighted** combines *scores* (a tunable `β` dial, but
> you must normalize first, because BM25 and cosine live on different scales). Fusing
> recovers the union of what each finds — the strongest retriever in this project.

## The intuition: they miss different things

- **BM25** nails exact tokens (names, IDs, `GPT-4.1`, error codes) but is blind to
  synonyms — query "car", document "automobile" → miss.
- **Semantic** nails meaning (car ≈ automobile) but blurs exact rare tokens — query
  "GPT-4.1" can pull generic AI passages instead of the one naming that version.

The important part: their mistakes **don't overlap**. Queries BM25 botches are often
ones semantic gets, and vice versa. So the *union* of their top results beats either
alone. That's the whole idea.

```
                query
        ┌─────────┴─────────┐        ← run both, independently, in PARALLEL
        ▼                   ▼
   BM25 (keyword)      semantic (vector)
        │                   │
   ranked list         ranked list
        └─────────┬─────────┘
                  ▼
             fuse rankings ─▶ top-k
```

(Both run *at the same time* over the same corpus — neither feeds the other.)

## Fusion method 1: RRF (combine ranks)

Reciprocal Rank Fusion ignores the raw scores and uses only **position** in each list:

```
RRF(d) = Σ over each list i:   1 / (k + rank_i(d))
```

`rank_i(d)` = d's position in list i (1 = top) · `k` = smoothing constant (default 60)
· `m` = number of lists (here 2: BM25 + semantic).

A document's score is the sum, across lists, of `1/(k + its rank)`. Sit near the top
of *both* lists → high total. Absent from a list → contributes 0 from it.

**Why the `k`?** Without it, `1/rank` makes rank 1 (`1.0`) a crushing 10× rank 10
(`0.1`) — a single first place would dominate everything. With `k=60`, rank 1 =
`1/61 ≈ 0.0164` and rank 10 = `1/70 ≈ 0.0143`: still ordered, but *gentle*, so both
retrievers get a real vote. Bigger `k` → flatter → exact rank matters less.

> RRF's superpower: using ranks lets it **sidestep the scale problem** below
> entirely — no normalization needed. That's why it's the robust default.

## Fusion method 2: weighted (combine scores)

Blend the actual scores with a dial `β` (how much to trust semantic):

```
hybrid = β · semantic_score + (1 − β) · keyword_score          0 ≤ β ≤ 1
```

`β = 0.5` = equal; lower β leans on exact keywords; higher β leans on meaning.

**The catch the naive formula hides:** BM25 scores run 0…30+ while cosine runs 0…1.
Blend them raw and BM25 silently dominates — `β` does nothing. You **must normalize
each list to a common range first** (we use **min–max**: rescale each list so its
best = 1 and worst = 0), *then* blend. Skip this and weighted fusion is quietly
broken.

## Which to use?

| | RRF | Weighted |
|---|---|---|
| combines | ranks | normalized scores |
| knob | `k` (smoothing) | `β` (keyword ↔ semantic trust) |
| scale-safe? | ✅ built in | ❌ must normalize first |
| feel | robust, set-and-forget | tunable to your data |

Start with **RRF**; reach for **weighted** when you want to deliberately favor one
retriever and are willing to tune.

## Metadata filtering (where does it fit?)

Metadata filters hard-drop docs that can't be right regardless of text score —
`language = en`, `tenant = A`, `version = v2`. The concrete question is *when*:

- **Pre-filter (preferred):** apply it **inside each retriever's query** as a `WHERE`
  clause, *before* scoring — BM25 and the vector search each only look at rows that
  pass. Both then hand fusion an already-clean list. Cheaper (you score fewer rows) and
  safe (a wrong-tenant doc can't even reach the ranking).
- **Post-filter:** retrieve, *then* drop non-matches. Simpler, but you can be left with
  too few results if most of the top-k get filtered out — and you scored docs you
  immediately threw away.

Rule of thumb: **filter first, per retriever, before fusion** — not after. (With ANN
it's a `WHERE` alongside the `<=>` search; a *very* selective filter can starve HNSW's
graph walk of matching neighbors — a real wrinkle — but the ordering still holds.)

## Key takeaways

- Hybrid wins because BM25 and semantic **miss different queries**; fusing recovers both.
- **RRF** = sum of `1/(k+rank)` across lists; `k` stops rank-1 from dominating; no
  normalization needed.
- **Weighted** = `β·semantic + (1−β)·keyword`, but **normalize scales first** or one
  side dominates.
- Run the two retrievers in **parallel**, then fuse.

---

**In this project:** [`search/fusion.ex`](../lib/learning_rag/search/fusion.ex)
implements *both* `rrf/2` and `weighted/1` (min–max normalized) as pure functions;
[`hybrid.ex`](../lib/learning_rag/search/hybrid.ex) runs BM25 + semantic over a
shared pool and fuses them. Both knobs are tunable from the CLI and UI —
`--method rrf --k 60` or `--method weighted --beta 0.5` (tweakable `k` and `β` were a
day-one goal). On SciFact, hybrid scores **NDCG@10 ≈ 0.757**, clearly above semantic
(0.71) and BM25 (0.69) — precisely because the two miss different queries.
