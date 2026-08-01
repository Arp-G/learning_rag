# LearningRag

A hands-on project for learning Retrieval-Augmented Generation (RAG) from the
retrieval side up, in Elixir + Phoenix with Postgres/pgvector. Every piece is
built to be read and understood: heavily commented, formulas visible in the
SQL, intermediate steps logged.

## Roadmap

| Phase | Focus | Status |
|-------|-------|--------|
| **1** | **Sparse retrieval** — TF-IDF & BM25 over an inverted index, IR evaluation metrics | ✅ done |
| 2 | Semantic search — OpenAI embeddings + pgvector | planned |
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
| [lib/learning_rag/eval/metrics.ex](lib/learning_rag/eval/metrics.ex) | Precision@K, Recall@K, MRR, MAP, NDCG@K |
| [lib/learning_rag/eval/runner.ex](lib/learning_rag/eval/runner.ex) | Runs a scorer over the test set, averages metrics |

## Tests

```bash
mix test        # or `mix precommit` for format + warnings-as-errors + tests
```

The search tests index a tiny hand-computable corpus and check the SQL scores
against the BM25/TF-IDF formulas re-implemented in Elixir — so any drift in the
SQL is caught exactly.
