# Query Rewriting — fixing the question before you search

> **TL;DR** — Users type short, vague, or follow-up questions ("what about the
> battery?"). Rewriting turns that into a clear, complete query *before* retrieval —
> by completing context, expanding synonyms, simplifying, or decomposing into
> sub-queries. A powerful trick is **HyDE**: embed a hypothetical *answer* instead of
> the question, because documents resemble answers more than questions. It's usually
> an extra LLM call, so it costs latency — and a bad rewrite can hurt.

## The intuition: garbage in, garbage out

Retrieval can only match what's in the query. Real queries are often poor search
input:

```
user: "What about the battery?"
   → rewrite → "What is the battery life of the Sony WH-1000XM6 headphones?"
```

The rewrite carries far more signal for the retriever. Fix the *question* and every
downstream stage improves — this is the one box in the pipeline that sits *before*
retrieval.

## The core techniques

- **Context completion** — resolve references ("it", "that", "the pricing") using the
  conversation so far.
  `"What about pricing?"` → `"What is the pricing for the GPT-5 API?"`
- **Query expansion** — add synonyms / related terms → higher **recall**.
  `"hotels with pools"` → `"hotels with indoor or outdoor swimming pools"`
- **Query simplification** — strip filler so the real intent stands out.
  `"I was wondering if you could maybe tell me…"` → `"Explain vector databases"`
- **Query decomposition** — break a multi-part question into sub-queries, retrieve
  each, then combine.
  `"Compare GPT-5 and Claude for coding and pricing"` → four focused queries
  (GPT-5 coding, Claude coding, GPT-5 pricing, Claude pricing).

Most production systems do this with a single **LLM call**
(`history + query → better query`).

## HyDE — embed a hypothetical answer

A clever twist for semantic search. Instead of embedding the *question*, have an LLM
write a **hypothetical answer** first, then embed *that*:

```
"How does HNSW work?"  ─▶  LLM drafts: "HNSW is a graph-based ANN algorithm that…"
                       ─▶  embed the draft  ─▶  retrieve documents similar to it
```

**Why it works:** in embedding space, a real document looks more like a well-written
*answer* than like a short, keyword-sparse *question*. Searching with an
answer-shaped vector lands closer to the right passages — especially for vague or
terse queries. (Risk: if the LLM hallucinates a wrong answer, you retrieve toward the
wrong region.)

## NER — pull out entities for filtering

Named Entity Recognition extracts structured fields from the query:

```
"Hotels in Paris under ₹10,000"  →  location = Paris, price ≤ 10000, category = hotel
```

Those become **metadata filters** or structured DB conditions alongside the text
search (a specialized model like GLiNER, or just an LLM, can do it).

## Costs and cautions

- ❌ Extra **LLM latency** and **cost** on every query.
- ❌ A **bad rewrite hurts** — it can drift from the user's real intent. Rewriting is
  not free accuracy; measure it.

## Key takeaways

- Rewriting improves the **query**, before retrieval (not the documents).
- Techniques: context completion, expansion (recall), simplification, decomposition.
- **HyDE**: embed a hypothetical answer — documents resemble answers, not questions.
- **NER** turns query phrases into metadata filters.
- Costs an LLM call, and a poor rewrite can backfire → evaluate it.
