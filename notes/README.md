# RAG Notes

Study notes on how Retrieval-Augmented Generation actually works — written to
**build intuition first**, then back it with a formula, a worked example, and a
diagram. They grew alongside the `learning_rag` project in this repo, so many
notes link to the real code and to the live search/eval tools.

How to read a note: each one opens with a **TL;DR** and a one-line mental model,
then the mechanics, an example, when to use it, and gotchas. Skim the TL;DR to
refresh in 30 seconds; read the rest when you want the "why".

## The RAG pipeline (the one picture to hold in your head)

RAG = let an LLM answer using **your** documents, by *finding the relevant bits
first* and pasting them into the prompt. Two phases:

```
1. INGEST  (once, offline)
   documents ─▶ chunk into passages ─▶ index them
                                        ├─ keyword index (postings)   → BM25/TF-IDF
                                        └─ vector index  (embeddings) → semantic

2. ANSWER  (every question)
   question ─▶ retrieve top passages ─▶ (re-rank) ─▶ build prompt ─▶ LLM ─▶ answer
              (keyword / vector / hybrid)            (question + passages)
```

Almost every note below is one box in this picture: how to chunk, how to index,
how to retrieve, how to re-rank, how to measure it, how to prompt with it.

## Learning path

Read roughly in this order. ✅ = written, ⬜ = coming.

**Foundations & retrieval**
1. ✅ [RAG vs Fine-Tuning](01-rag-vs-fine-tuning.md) — when RAG is the right tool
2. ✅ [TF-IDF & BM25](02-tf-idf-and-bm25.md) — keyword (sparse) retrieval
3. ✅ [Vectors & Embeddings](03-vectors-and-embeddings.md) — turning meaning into numbers
4. ✅ [Semantic Search](04-semantic-search.md) — retrieval by meaning
5. ✅ [Searching Algorithms](05-searching-algorithms.md) — how keyword (inverted index) & vector (HNSW) search run
6. ✅ [Hybrid Search](06-hybrid-search.md) — combining keyword + semantic
7. ✅ [Re-Ranking](07-re-ranking.md) — reordering the shortlist

**The input side**
8. ✅ [Chunking](08-chunking.md) — splitting documents into passages
9. ✅ [Advanced Chunking](09-advanced-chunking.md) — smarter splitting
10. ✅ [Query Rewriting](10-query-rewriting.md) — fixing the question before you search

**Measuring it**
11. ✅ [Retrieval Evaluation Metrics](11-retrieval-evaluation-metrics.md) — Precision@K, Recall, MRR, MAP, NDCG

**Generation**
12. ✅ [Prompt Engineering](12-prompt-engineering.md) — the prompt you build around the passages
13. ✅ [Evaluating LLM Performance](13-evaluating-llm-performance.md) — grading the answer (faithfulness, relevancy)

**Systems & advanced**
14. ✅ [Agentic RAG](14-agentic-rag.md) — multi-step, tool-using retrieval
15. ✅ [Production RAG](15-production-rag.md) — quality vs latency vs cost, caching, guardrails, observability

**LLM background** (useful context, not RAG-specific)
16. ✅ [Sampling Strategies](16-sampling-strategies.md) — temperature, top-k, top-p
17. ✅ [LLM Characteristics & Benchmarks](17-llm-characteristics.md) — picking a model

📖 [Glossary](glossary.md) — shared terms (vector, embedding, cosine, recall, ANN, sparse/dense…) so no note has to redefine them.

## Where this meets the code

These notes are the theory behind the working implementation in this repo:

| Note | Built in |
|------|----------|
| TF-IDF & BM25 | [`search/bm25.ex`](../lib/learning_rag/search/bm25.ex), [`tf_idf.ex`](../lib/learning_rag/search/tf_idf.ex) |
| Semantic Search / Searching Algorithms | [`search/semantic.ex`](../lib/learning_rag/search/semantic.ex) (pgvector, exact + HNSW) |
| Hybrid Search | [`search/fusion.ex`](../lib/learning_rag/search/fusion.ex), [`hybrid.ex`](../lib/learning_rag/search/hybrid.ex) |
| Retrieval Evaluation Metrics | [`eval/metrics.ex`](../lib/learning_rag/eval/metrics.ex) |

Run `mix phx.server` to try each idea live on the search and evaluate pages.
