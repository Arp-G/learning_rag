# LearningRag

📓 Study notes: [RAG on Notion](https://app.notion.com/p/RAG-3a77b0f8661080d0beeac65d87b80ac8)

An educational project for learning Retrieval-Augmented Generation (RAG) hands-on,
from the retrieval side up. It builds each layer of a search stack — sparse
(TF-IDF, BM25), dense (embeddings), and hybrid — and measures them against a real
benchmark, so the tradeoffs are concrete rather than abstract. The code is heavily
commented and the scoring math lives in visible SQL. It's written in Elixir/Phoenix
with **Postgres + pgvector** (chosen so the whole thing runs on one familiar
database, no separate vector store) and evaluated on **SciFact** — a
[BEIR](https://github.com/beir-cellar/beir) benchmark of ~5.2K scientific abstracts
with 300 human-labeled queries.

## Setup

Requires Docker (for Postgres) and Elixir (see `.tool-versions`). An
`OPENAI_API_KEY` is needed only for the embedding step (semantic/hybrid search).

```bash
bin/setup                      # start Postgres in Docker + deps + create/migrate DB
mix rag.download               # fetch the SciFact dataset (~3 MB)
mix rag.index                  # load, chunk, and build the inverted index

export OPENAI_API_KEY=sk-...   # embeddings only
mix rag.embed                  # embed chunks + queries (~$0.04, one-time)
```

Postgres runs on host port **5434**; the container must be up for `mix test`.

## Usage

**Command line**

```bash
# Search, with a per-result score breakdown. Scorers: bm25 | tfidf | semantic | hybrid
mix rag.search "vitamin D deficiency and bone fractures" --scorer bm25 --k1 1.2 --b 0.75
mix rag.search "..." --scorer semantic
mix rag.search "..." --scorer hybrid --method weighted --beta 0.5

# Evaluate a scorer over the 300 SciFact queries
mix rag.eval --scorer bm25
mix rag.eval --scorer hybrid --method rrf --k 60

# Compare exact vs HNSW approximate vector search (recall + latency)
mix rag.ann
```

**Web UI** — `mix phx.server`, then <http://localhost:4000>: search with live
parameter tuning, plus an evaluation page that stacks runs into a comparison table.

![Web UI screenshot](docs/ui.png)
<!-- drop a screenshot at docs/ui.png -->

## Metrics

Mean over the 300 SciFact test queries. NDCG@10 is the headline metric; the
published SciFact **BM25 baseline is ≈ 0.665**, which our BM25 matches (0.694),
confirming the implementation.

| Scorer | NDCG@10 | MRR@10 | Recall@10 |
|--------|:-------:|:------:|:---------:|
| TF-IDF | 0.539 | 0.487 | 0.727 |
| BM25 | 0.694 | 0.659 | 0.828 |
| Semantic (OpenAI `text-embedding-3-small`) | 0.712 | 0.676 | 0.851 |
| **Hybrid** (weighted, β=0.5) | **0.757** | **0.726** | **0.875** |

Quality improves at each step; hybrid wins because BM25 and semantic miss
*different* queries, so fusing them recovers the union. On the ANN side, HNSW
returns ~99% of the exact top-10 at a fraction of the latency (`mix rag.ann`).

## How it works

```
documents ─▶ chunks ─▶ postings (sparse) + embedding (dense)      queries + qrels (ground truth)
```

- **Chunks** are the retrieval unit. **Postings** are the inverted index used by
  BM25/TF-IDF; **embedding** is the pgvector column used by semantic search.
- Scoring lives in **SQL with the formula visible** — BM25/TF-IDF as named CTEs,
  semantic as cosine distance. **Hybrid** fuses the two rankings in Elixir, either
  by rank (RRF) or by blending normalized scores (weighted).
- Evaluation retrieves chunks, collapses them to parent documents, and grades the
  ranking against the qrels.

### Key modules

| Path | What |
|------|------|
| [ingest/chunker.ex](lib/learning_rag/ingest/chunker.ex) | Overlapping word-window chunking |
| [ingest/indexer.ex](lib/learning_rag/ingest/indexer.ex) | Load → chunk → build the inverted index (SQL) |
| [search/bm25.ex](lib/learning_rag/search/bm25.ex) · [tf_idf.ex](lib/learning_rag/search/tf_idf.ex) | Sparse scoring in SQL |
| [search/semantic.ex](lib/learning_rag/search/semantic.ex) | Dense/cosine search (pgvector), exact + HNSW |
| [search/fusion.ex](lib/learning_rag/search/fusion.ex) · [hybrid.ex](lib/learning_rag/search/hybrid.ex) | RRF / weighted fusion |
| [embed/openai.ex](lib/learning_rag/embed/openai.ex) | OpenAI embeddings via Req, behind a swappable behaviour |
| [eval/metrics.ex](lib/learning_rag/eval/metrics.ex) · [runner.ex](lib/learning_rag/eval/runner.ex) | IR metrics (P@K, R@K, MRR, MAP, NDCG) + eval runner |
