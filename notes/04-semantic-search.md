# Semantic Search — retrieval by meaning

> **TL;DR** — Embed the query with the *same* model used for the documents, then
> rank documents by how close their vectors sit to the query's (cosine). You get
> matches on **meaning** — synonyms and paraphrases keyword search misses — at the
> cost of an embedding model, more compute, and a few characteristic blind spots
> (exact tokens, negation, out-of-domain jargon).

## The pipeline

```
query ─▶ embedding model ─▶ query vector
                                   │  compare (cosine) to every document vector
                                   ▼
                        rank by similarity ─▶ top-k
```

That's the whole thing. Documents were embedded once, up front (when the corpus is
indexed); at query time you embed just the query and find its nearest document
vectors. *Why* nearby vectors mean similar text is the previous note —
[Vectors & Embeddings](03-vectors-and-embeddings.md).

## The one rule you can't break: same model on both sides

Query and documents **must be embedded by the same model.** Each model learns its
own coordinate system — its dimensions mean different things. A vector from model A
and one from model B are two different languages; comparing them produces
meaningless numbers that *don't* error — they just quietly rank wrong.

> Corollary: switch your embedding model and you must **re-embed the entire
> corpus**, not only the new documents.

## Similarity is not the same as relevance

Cosine tells you two texts are *about the same thing* — which usually, but not
always, means one answers the other. The classic trap is **negation**:

```
"aspirin prevents heart attacks"
"aspirin does not prevent heart attacks"
```

Same words, same topic → these embed almost identically, yet mean the opposite.
More generally, a passage can be highly *similar* to the query without actually
*answering* it. That gap is why strong systems add a
[re-ranker](07-re-ranking.md) (reads query + passage *together* to judge real
relevance) and often mix in [hybrid](06-hybrid-search.md) keyword signals.

## Strengths and limits

- ✅ **Meaning, not spelling** — synonyms, paraphrases, related concepts; connects
  phrasings a keyword index never would.
- ❌ **Costs a model + compute** — every query needs an embedding call, and comparing
  against every vector is O(N) (the next note fixes the speed).
- ❌ **Weak on exact/rare tokens** — IDs, codes, surnames — and on **domain jargon**
  the embedding model never saw in training (a general model has fuzzy vectors for
  niche terms).
- ❌ **Opaque** — no per-word explanation of *why* something matched.

Because these blind spots differ from BM25's, the two are natural partners →
[Hybrid Search](06-hybrid-search.md).

## The scale problem (bridge to the next note)

"Compare against every document vector" is fine for thousands of docs but becomes
the bottleneck at millions — O(N) per query, on vectors of 1536 numbers each.
[Searching Algorithms](05-searching-algorithms.md) is how you avoid checking every
vector.

## Key takeaways

- Semantic search = embed query → nearest document vectors by cosine → top-k.
- **Same embedding model** for query and documents, always; changing it means
  re-embedding everything.
- **Similar ≠ relevant** (negation is the classic failure) → re-rankers and hybrid help.
- Beats keyword on meaning; loses on exact tokens and unseen jargon.

---

**In this project:** [`search/semantic.ex`](../lib/learning_rag/search/semantic.ex)
runs the ranking in SQL — `1 - (embedding <=> $1) AS score`, ordered by cosine
distance. Query embeddings for the 300 eval queries are computed once and **stored**,
so `mix rag.eval --scorer semantic` makes *zero* API calls. On SciFact, semantic
scores NDCG@10 ≈ 0.71 — a touch above BM25's ~0.69, because these are
exact-terminology science claims where keyword matching is already strong. The real
win comes from combining the two.
