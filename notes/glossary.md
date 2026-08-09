# Glossary

Shared terms used across the notes. Each note links here instead of re-defining
them. Kept deliberately short — one or two lines each.

## Documents & text

- **Corpus** — the whole collection of documents you can search over.
- **Document** — one source item (an article, a PDF, a web page).
- **Chunk** (passage) — a small slice of a document. RAG retrieves *chunks*, not
  whole documents, so the model gets a focused, relevant piece.
- **Token** — the unit an LLM/embedder reads; roughly ¾ of a word. "chunking" ≈ 2 tokens.

## Representing text as numbers

- **Vector** — a list of numbers, i.e. the coordinates of a point in space.
- **Embedding** — a vector produced by a trained model that captures *meaning*:
  texts with similar meaning get nearby vectors. Usually a few hundred to a few
  thousand numbers long (OpenAI's `text-embedding-3-small` = 1536).
- **Sparse vs dense** —
  - *Sparse*: one dimension per vocabulary word; almost all zeros (a chunk only
    uses a few hundred of ~30k words). This is what keyword search (BM25) uses.
  - *Dense*: a few hundred/thousand numbers, all non-zero, capturing meaning.
    This is what embeddings/semantic search use.
- **Inverted index / postings** — a table of "word → which chunks contain it, and
  how often." It *is* the sparse matrix, stored as only its non-zero cells. Powers
  keyword search.

## Measuring similarity

- **Cosine similarity** — how aligned two vectors' *directions* are, ignoring
  length. +1 = same direction, 0 = unrelated, −1 = opposite. The default for
  comparing embeddings.
- **Cosine distance** — just `1 − cosine similarity`; smaller = closer. Databases
  (pgvector's `<=>`) return distance, so we flip it to a similarity score.
- **Dot product** — multiply matching components and sum. For *unit-length*
  (normalized) vectors it equals cosine similarity; embeddings are usually
  normalized, so the two agree.
- **Euclidean distance** — straight-line distance between two points. Cares about
  length as well as direction, so it's used less for embeddings.

## Searching

- **Nearest-neighbor search / KNN** — find the k vectors closest to the query
  vector. *Exact* KNN compares against every vector (accurate but O(N)).
- **ANN (approximate nearest neighbor)** — skip most vectors using a clever index
  (e.g. HNSW), trading a little accuracy for a big speedup. Essential at scale.
- **HNSW (Hierarchical Navigable Small World)** — the most common ANN index: a layered
  graph you navigate (top-layer "express" jumps → fine local hops) to reach near
  vectors fast. Tuned per query by `ef_search` (higher = better recall, slower).
- **Recall** (of an ANN search) — of the true top-k neighbors, what fraction the
  approximate search actually found. 1.0 = same as exact. (Different from
  retrieval *Recall@K* — see the metrics note.)
- **top-k** — keep only the k highest-scoring results.
- **Re-ranking** — take the retriever's top-N shortlist and reorder it with a
  slower, more accurate model.
- **Bi-encoder** — embeds the query and each document *separately*, then compares
  vectors. Fast (documents pre-embedded); used for retrieval.
- **Cross-encoder** — feeds query + document *together* into one model for a
  relevance score. Slower but more accurate; used for re-ranking the shortlist.

## Evaluation

- **Ground truth / relevance judgments / qrels** — human labels saying which
  documents are relevant for each test query. The answer key metrics compare
  against.
- **Baseline** — a published/standard score for a method on a dataset, used to
  sanity-check your implementation.

## Retrieval metrics

Each scores one query's ranking against the qrels; you average over all queries. Full
detail + worked examples in the [metrics note](11-retrieval-evaluation-metrics.md).

- **Precision@K** — of the top K results, the fraction that are relevant. "Few duds."
- **Recall@K** — of all relevant docs, the fraction that reach the top K. "Few misses."
- **MRR (Mean Reciprocal Rank)** — mean of `1 / rank-of-first-hit` across queries;
  rewards putting *a* relevant doc high.
- **MAP (Mean Average Precision)** — mean average precision across queries; rewards
  putting *all* relevant docs high.
- **NDCG (Normalized Discounted Cumulative Gain)** — like MAP but uses *graded*
  relevance and a log position-discount, normalized to 0…1. The headline IR metric.
- **Relevance grade / binary relevance** — a grade rates how relevant a doc is
  (0 = no … 3 = perfect). Only NDCG uses grades; Precision/Recall/MRR/MAP treat
  relevance as **binary** (relevant or not, 1/0).
