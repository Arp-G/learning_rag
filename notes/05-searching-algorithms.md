# Searching Algorithms — how keyword and vector search actually run

> **TL;DR** — Two kinds of search, two speed tricks. **Keyword** search finds the
> chunks containing your words with an **inverted index** (a "word → which chunks"
> lookup), so it never scans the whole corpus. **Semantic** search finds the nearest
> vectors; comparing against *every* vector is O(N), so **approximate indexes like
> HNSW** skip almost all of them. Same goal both times: don't look at everything.

## Two searches, two speed problems

You've met both retrieval styles already — [keyword/BM25](02-tf-idf-and-bm25.md) and
[semantic](04-semantic-search.md). Scoring aside, each faces the same *"how do I do
this without checking all N chunks?"* problem, and each solves it with a different
index:

| | keyword search | semantic search |
|---|---|---|
| match on | exact words | vector closeness |
| naive cost | scan every chunk for the word | compare query to every vector |
| the index | **inverted index** (postings) | **ANN index** (HNSW) |

## Keyword search: the inverted index

To find chunks containing "vitamin", you *could* read every chunk and look — O(N).
Instead you build the lookup **once**, the other way around:

```
inverted index (postings):
  "vitamin"  → [chunk 3 (×2), chunk 41 (×1), chunk 88 (×1)]
  "fracture" → [chunk 3 (×1), chunk 12 (×3)]
```

A query only ever touches the postings for *its own* words, so you jump straight to
the handful of chunks that could match and ignore the millions that can't. That
"word → chunks that contain it, and how often" table **is** the sparse matrix from
[TF-IDF & BM25](02-tf-idf-and-bm25.md); BM25 then scores just those candidates.

### How this differs from Postgres full-text search

Postgres ships its *own* keyword search — `to_tsvector @@ to_tsquery` matching, a
**GIN** index, and a ranking function `ts_rank`. This project **reuses Postgres's
tokenizer** (`to_tsvector` handles stemming and stopwords, for both the documents and
the query) but **builds its own `postings` table and computes BM25 in SQL** instead
of calling `ts_rank`. Why? `ts_rank` isn't BM25 — it's a simpler tf-based score — and
hand-rolling the index lets us *see and tune* the formula (and `SELECT * FROM
postings` to inspect the sparse matrix directly). In a real app, native GIN full-text
search is the batteries-included choice; we traded that convenience for transparency.

## Semantic search: nearest-neighbor

Semantic search ends in "compare the query vector to the document vectors and take
the closest." Do that against *all* of them and you have **KNN** (k-nearest
neighbors), the exact method:

```
query ─▶ cosine vs EVERY vector ─▶ sort ─▶ top-k
```

- ✅ Returns the **true** nearest neighbors — as accurate as it gets.
- ❌ **O(N)** per query. At 10 million 1536-D vectors, every search touches all ten
  million. That's the wall.

### ANN: trade a little accuracy for a lot of speed

**Approximate** nearest neighbors gives up "guaranteed exact" for "very close, much
faster":

```
exact top-3:  A(1.00)  B(0.99)  C(0.98)
ANN   top-3:  A(1.00)  B(0.99)  D(0.975)   ← swapped one near-tie, but ~50× faster
```

We measure the slip with **recall** — of the true top-k, what fraction the
approximate search actually returned ([recall in the glossary](glossary.md#searching)). Good
ANN keeps recall ~0.95–0.99 while skipping almost all the work. The trick is always
the same: **build an index that groups similar vectors, then explore only the
promising regions** at query time. HNSW, IVF, and LSH are different ways to do that —
**ANN is the family, HNSW is one member.**

### HNSW: a navigable graph with express lanes

HNSW (Hierarchical Navigable Small World) stores vectors as a **graph** — each
vector linked to its nearest few — and searches by *walking* the graph toward the
query instead of scanning a list.

The clever part is a **hierarchy** of layers:

```
Layer 2 (sparse)   ●───────────────●        few nodes, long "express" jumps
                    \              /
Layer 1 (mid)    ●───●────●────●───●         more nodes, medium hops
                 │   │    │    │   │
Layer 0 (all)  ●─●─●─●─●─●─●─●─●─●─●─●        every vector, fine local links
```

Search is like **Google Maps**: take the highway (top layer) to jump near the
destination, then drop to city roads and local streets (lower layers) to home in.

```
enter at top ─▶ greedily hop to the nearest neighbor ─▶ drop a layer ─▶ … ─▶ layer 0, take top-k
```

Because the walk is **greedy** (always steps to the closest neighbor it can see, no
exhaustive backtracking), it can settle in a *locally* best spot and miss the true
global nearest — which is exactly why HNSW is *approximate*. Vectors are inserted one
at a time, each linking to the nearest neighbors it finds by navigating the existing
graph — so the graph builds itself without ever comparing against everything.

### The three knobs

| knob | when | meaning | trade |
|---|---|---|---|
| **`m`** | build | links kept per node | higher → better recall, more memory |
| **`ef_construction`** | build | candidates examined while inserting | higher → better graph, slower build |
| **`ef_search`** | query | candidates examined per search | **higher → better recall, slower query** |

`ef_search` is the dial you turn at query time to slide along the recall↔latency
tradeoff. `m` and `ef_construction` are fixed once, when the index is built.

### What this project measured (and an honest surprise)

`mix rag.ann` runs the 300 stored query vectors through **exact** vs **HNSW at
`ef_search ∈ {10, 40, 100, 200}`**, reporting recall@10 and latency:

- Recall climbs toward **~0.99** as `ef_search` rises — the dial behaves as promised.
- **The surprise:** at only ~7.7k chunks, pushing `ef_search` *high* made Postgres's
  planner decide the index wasn't worth it and **fall back to a full scan** (seq scan
  ~64 ms) — so "more accurate" briefly became "slower, via brute force," while
  `ef_search=40` used the index at ~4 ms.

Lesson: at thousands of rows, **exact search is already a few milliseconds**, so
HNSW's payoff here is *educational*. The speedup becomes decisive at millions of
vectors — the scale ANN actually exists for.

## KNN vs ANN vs HNSW

| | KNN (exact) | ANN (family) | HNSW |
|---|:---:|:---:|:---:|
| exact results | ✅ | ❌ | ❌ |
| speed | slow, O(N) | fast | very fast |
| scales to millions | ❌ | ✅ | ✅ |
| checks every vector | ✅ | ❌ | ❌ |

## Key takeaways

- **Keyword** search runs on an **inverted index** (postings): jump straight to the
  chunks that contain your words; never scan the rest.
- We reuse Postgres's tokenizer but score **BM25** ourselves — not pg's native
  `ts_rank` full-text search.
- **Semantic** search is nearest-neighbor: exact **KNN** is O(N); **ANN** trades a
  little **recall** for big speed; **HNSW** is a layered graph navigated highway→street.
- **`ef_search`** trades recall for latency at query time; the tradeoff only *matters*
  at large N.

---

**In this project:** the keyword side is the `postings` inverted index built in
[`ingest/indexer.ex`](../lib/learning_rag/ingest/indexer.ex) (one SQL statement — you
can `SELECT * FROM postings` and see the sparse matrix). The vector side is the HNSW
index `USING hnsw (embedding vector_cosine_ops)` (the op-class must match the `<=>`
cosine operator), built with pgvector's defaults (`m=16`, `ef_construction=64`);
[`search/semantic.ex`](../lib/learning_rag/search/semantic.ex) sets `hnsw.ef_search`
per query and forces exact search (`enable_indexscan=off`) for the baseline. Compare
them with `mix rag.ann`.
