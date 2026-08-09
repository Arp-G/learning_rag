# Re-Ranking — reordering the shortlist

> **TL;DR** — First-stage retrieval (BM25 / semantic / hybrid) is fast but ranks by a
> cheap signal, so the *order* isn't its strength. A **re-ranker** takes the top ~50
> and rescores them with a slower, more accurate model that reads **query + passage
> together** (a cross-encoder), then keeps the top ~5 for the LLM. You pay the
> expensive model only on a tiny shortlist → near-best quality at a fraction of the cost.

## Why a second stage at all?

Retrieval has to be cheap because it scores the *whole corpus*. That cheapness is
exactly why its ordering is imperfect — recall "similar ≠ relevant" from
[Semantic Search](04-semantic-search.md): the nearest vector isn't always the best
answer. So split the job in two:

```
query ─▶ retrieve (fast, whole corpus) ─▶ top 50 ─▶ re-rank (slow, accurate) ─▶ top 5 ─▶ LLM
         recall: "don't miss it"                    precision: "put the best first"
```

Retrieval maximizes **recall** (get the good ones *somewhere* in the top 50);
re-ranking maximizes **precision** (get the best few to the *very top*).

## Bi-encoder vs cross-encoder (the key contrast)

The split comes down to two model shapes — the [bi-encoder](glossary.md#searching)
that retrieval uses, and the [cross-encoder](glossary.md#searching) a re-ranker uses.
Here's *why* one is fast and the other is accurate.

**Bi-encoder** (what retrieval uses): embeds query and document **separately**, then
compares vectors.

```
query    ─▶ [vector] ┐
                     ├─ cosine        (documents pre-embedded once → ANN makes it fast)
document ─▶ [vector] ┘
```

Because documents are embedded ahead of time, it scales to millions. But query and
document never "meet" until the final dot product — a shallow interaction.

**Cross-encoder** (what re-ranking uses): feeds query **and** document **together**
through one model that reads them jointly and outputs a relevance score.

```
[query + document] ─▶ model ─▶ relevance 0…1
```

It sees how *this* query relates to *this* passage word-by-word (including
negation), so it's far more accurate — the direct fix for "similar but wrong."

## Why not cross-encode everything?

Because you **can't precompute** it. A bi-encoder embeds each document once; a
cross-encoder's score depends on the query, so for a new query it must run the full
model on *every* (query, document) pair:

```
1,000,000 docs → 1,000,000 model passes per query    ✗ hopeless
top 50 (from retrieval) → 50 model passes per query   ✓ trivial
```

Hence the two-stage pattern: cheap retrieval narrows a million down to 50; the
expensive model ranks only those 50.

## ColBERT — the middle ground

A bi-encoder squashes a whole passage into **one** vector (fast, but detail is lost);
a cross-encoder compares every word jointly (accurate, but nothing precomputes).
**ColBERT** splits the difference: keep **one vector per token** (word), not one per
document.

The trick is called **late interaction**: query and document are encoded *separately*
(so the document's token-vectors can be precomputed, like a bi-encoder), but they
*interact* only at scoring time. Each query token finds its **single best-matching**
document token by similarity, and those bests are summed — **MaxSim**:

```
score = Σ over query tokens q of:  ( max over doc tokens d of  sim(q, d) )
```

Intuition: *does every word in my query find a good match somewhere in the passage?*
That word-level matching is far richer than one-vector-against-one-vector, yet still
fast because the document vectors are precomputed. The cost is **storage** — a vector
per token instead of per document — plus more complex indexing.

| method | speed | quality | storage |
|---|:---:|:---:|:---:|
| bi-encoder (retrieve) | ★★★★★ | ★★★ | low |
| cross-encoder (re-rank) | ★ | ★★★★★ | low |
| ColBERT | ★★★ | ★★★★½ | high |

## Where it sits in the pipeline

```
query ─▶ (query rewrite) ─▶ hybrid retrieve ─▶ top 50 ─▶ cross-encoder / ColBERT ─▶ top 5 ─▶ LLM
```

The re-ranker only ever sees a small candidate set, so production RAG stays both
fast and accurate.

## Key takeaways

- Retrieval optimizes **recall** + speed; re-ranking optimizes **precision** on a shortlist.
- **Bi-encoder** = separate embeddings, precomputable, fast → retrieval.
  **Cross-encoder** = joint encoding, query-dependent, accurate → re-ranking.
- You can't precompute cross-encoder scores → run it only on the top ~50.
- **ColBERT** trades storage for precomputable, near-cross-encoder quality via
  token-level MaxSim.
