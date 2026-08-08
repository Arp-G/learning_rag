# LearningRag

A hands-on project for learning Retrieval-Augmented Generation (RAG) from the
retrieval side up, in Elixir + Phoenix with Postgres/pgvector. Every piece is
built to be read and understood: heavily commented, formulas visible in the
SQL, intermediate steps logged.

## Roadmap

| Phase | Focus | Status |
|-------|-------|--------|
| **1** | **Sparse retrieval** — TF-IDF & BM25 over an inverted index, IR evaluation metrics | ✅ done |
| **2** | **Semantic search** — OpenAI embeddings + pgvector, exact + HNSW approximate NN | ✅ done |
| 3 | Hybrid search — combine sparse + dense | planned |
| 4 | LiveView UI — upload, search, tweak parameters, visualize metrics | planned |

Phase 1 is evaluated on **SciFact** (a [BEIR](https://github.com/beir-cellar/beir)
benchmark: ~5.2K scientific abstracts, 300 test queries with human relevance
judgments). Published baselines let us verify our implementation — our BM25
gets **NDCG@10 ≈ 0.69**, in line with the published ~0.665.

## Setup

Requires Docker (for Postgres) and Elixir (see `.tool-versions`).

```bash
bin/setup            # starts Postgres in Docker, installs deps, creates + migrates the DB
mix rag.download     # fetches the SciFact dataset into priv/data/ (~3 MB)
mix rag.index        # loads → chunks → builds the inverted index (~6s)
```

Postgres runs in Docker on host port **5434** (to avoid clashing with other
local Postgres instances). The container must be running for `mix test` and
`mix precommit`.

## Usage

```bash
# Search, with a per-term score breakdown
mix rag.search "vitamin D deficiency and bone fractures" --scorer bm25 --top 5
mix rag.search "..." --scorer tfidf

# Tweak BM25 parameters live (no reindexing — they're query-time values)
mix rag.search "..." --scorer bm25 --k1 1.2 --b 0.75

# Evaluate a scorer over all 300 SciFact queries
mix rag.eval --scorer bm25
mix rag.eval --scorer tfidf
mix rag.eval --scorer bm25 --k1 1.2 --b 0.75
```

Sample results (mean over 300 queries):

| Metric | BM25 | TF-IDF |
|--------|------|--------|
| NDCG@10 | 0.694 | 0.539 |
| MRR@10 | 0.659 | 0.487 |
| Recall@10 | 0.828 | 0.727 |

The ~15-point NDCG gap is exactly what BM25's term-frequency saturation (`k1`)
and length normalization (`b`) buy you over plain TF-IDF. Precision@K looks
small (~0.1) only because SciFact averages ~1.1 relevant documents per query —
recall, MRR and NDCG are the informative numbers here.

## Semantic search & HNSW (Phase 2)

Instead of matching words, semantic search matches *meaning*: each chunk and the
query become a 1536-dim vector (OpenAI `text-embedding-3-small`), and we rank by
cosine similarity using [pgvector](https://github.com/pgvector/pgvector).

```bash
export OPENAI_API_KEY=sk-...       # needed only for embedding
mix rag.embed                      # embed all chunks + queries (~$0.04, one-time, idempotent)

mix rag.search "how does vitamin D affect bone health" --scorer semantic
mix rag.eval --scorer semantic     # uses stored query vectors — no API calls
mix rag.ann                        # exact vs HNSW: recall@10 + latency across ef_search
```

- **Cosine, not keywords.** `<=>` is pgvector's cosine distance; we report
  `1 - distance` as the score. A chunk can rank high with zero shared words.
- **Exact vs approximate.** Search is exact (full scan) by default, or uses the
  HNSW index; `mix rag.ann` measures the index's recall and speed against the
  exact baseline as `ef_search` grows — the tradeoff that matters at millions of
  vectors.
- **Embeddings are stored, not recomputed.** `mix rag.embed` fills the
  `chunks.embedding` / `queries.embedding` columns, so evaluation never re-calls
  OpenAI.

## Observations

The same 300 SciFact queries, run through all three scorers — quality goes up at
each step:

| Metric (mean over 300 queries) | TF-IDF | BM25 | Semantic |
|--------------------------------|--------|------|----------|
| NDCG@10     | 0.539 | 0.694 | 0.712 |
| MRR@10      | 0.487 | 0.659 | 0.676 |
| Recall@10   | 0.727 | 0.828 | 0.851 |
| Precision@5 | 0.137 | 0.161 | 0.176 |

In plain terms:

- **BM25 clearly beats plain TF-IDF** (~15 NDCG points). Flattening repeated
  words and adjusting for chunk length — BM25's two knobs — is what does it.
- **Semantic beats BM25, but only a little** (0.712 vs 0.694). SciFact is
  scientific claims full of exact terms, so keyword matching is already strong;
  embeddings mainly help when the wording differs (synonyms, paraphrases).
  Because the two methods win on *different* queries, combining them is the next
  step — Phase 3 (hybrid).

### Exact vs HNSW (speed)

Semantic search can find the nearest vectors two ways: check every chunk
(exact), or use the HNSW index (approximate — it skips most chunks). Over the
300 queries:

| Search              | recall@10 | latency |
|---------------------|-----------|---------|
| HNSW, ef_search=10  | 0.925     | ~3 ms   |
| HNSW, ef_search=40  | 0.993     | ~3 ms   |
| exact (full scan)   | 1.000     | ~41 ms  |

- **The index is ~12× faster for a tiny accuracy cost.** At `ef_search=40` it
  finds 99% of the exact top-10 in a fraction of the time. `ef_search` is the
  effort dial: higher = more accurate but slower.
- **Push `ef_search` high enough and Postgres quietly goes back to the exact
  scan.** pgvector makes the index look more expensive as `ef_search` grows, so
  past a point the planner decides a full scan is cheaper and uses that instead
  (`EXPLAIN` shows `Index Scan` turn into `Seq Scan`). At our ~7.7k chunks that
  happens early; with millions of vectors the index wins easily and stays the
  only practical choice.

## How it works

```
documents ──▶ chunks ──▶ postings           queries ──▶ qrels
(abstracts)  (passages)  (inverted index)   (test set)  (answer key)
```

- **Chunks** are the retrieval unit — passages cut from documents.
- **Postings** are the inverted index: one row per `(term, chunk, tf)`. This
  *is* the sparse term×chunk matrix, stored as its nonzero cells. A BM25 score
  is a sparse dot product over these rows.
- **Linguistics vs ranking are separated on purpose.** Postgres
  `to_tsvector('english', …)` does tokenization, stop-word removal, and
  stemming — nothing else (never `ts_rank`/`@@`). All ranking math is our own
  SQL, with the formula written out as named CTEs in
  [`bm25.ex`](lib/learning_rag/search/bm25.ex) and
  [`tf_idf.ex`](lib/learning_rag/search/tf_idf.ex).
- **The same `to_tsvector('english', …)` runs on both documents and queries**,
  so their terms line up by construction.
- **Retrieval is chunk-level; qrels judge documents.** The eval runner maps
  chunk hits to parent documents (best chunk per document) before grading.

### Key modules

| Path | What |
|------|------|
| [lib/learning_rag/ingest/chunker.ex](lib/learning_rag/ingest/chunker.ex) | Overlapping word-window chunking |
| [lib/learning_rag/ingest/indexer.ex](lib/learning_rag/ingest/indexer.ex) | Load → chunk → build postings (the SQL inverted-index build) |
| [lib/learning_rag/search/bm25.ex](lib/learning_rag/search/bm25.ex) | BM25 scoring in SQL |
| [lib/learning_rag/search/tf_idf.ex](lib/learning_rag/search/tf_idf.ex) | TF-IDF scoring in SQL (contrast) |
| [lib/learning_rag/search/semantic.ex](lib/learning_rag/search/semantic.ex) | Dense/cosine search in SQL (pgvector), exact + HNSW modes |
| [lib/learning_rag/embed/openai.ex](lib/learning_rag/embed/openai.ex) | Embeds text via OpenAI (Req), behind a swappable behaviour |
| [lib/learning_rag/eval/metrics.ex](lib/learning_rag/eval/metrics.ex) | Precision@K, Recall@K, MRR, MAP, NDCG@K |
| [lib/learning_rag/eval/runner.ex](lib/learning_rag/eval/runner.ex) | Runs a scorer over the test set, averages metrics |

## Tests

```bash
mix test        # or `mix precommit` for format + warnings-as-errors + tests
```

The search tests index a tiny hand-computable corpus and check the SQL scores
against the BM25/TF-IDF formulas re-implemented in Elixir — so any drift in the
SQL is caught exactly.
