# Production RAG — quality vs latency vs cost, caching, guardrails, observability

> **TL;DR** — A production RAG system is a **pipeline of independently tunable
> stages**, not one LLM call, and every choice trades off three things: **quality**,
> **latency**, and **cost** — improving one usually hurts another. Around that
> pipeline you add **caching** (speed + cost), **guardrails** (safety + validity),
> **hallucination controls** (grounding), and **observability** (so you can tell *why*
> an answer happened).

## The triangle you're always balancing

```
        quality
         /   \
        /     \
   latency ─── cost
```

Every knob moves you around it:

| change | quality | latency | cost |
|---|:---:|:---:|:---:|
| cross-encoder re-ranking | ▲ | ▼ slower | ▼ pricier |
| bigger generator model | ▲ | ▼ | ▼ |
| retrieve more chunks | ▲ recall | ▼ | ▼ tokens |
| caching | – | ▲ faster | ▲ cheaper |

There's no free lunch — "make it better" always means choosing *which* of the three
you'll spend. Naming the tradeoff is half the job.

## The production pipeline

Each stage is separately tunable and measurable:

```
query ─▶ input validation ─▶ (query rewrite) ─▶ hybrid retrieve ─▶ metadata filter
      ─▶ re-rank ─▶ build prompt ─▶ LLM ─▶ output validation ─▶ response
```

Most stages are their own note — [rewrite](10-query-rewriting.md),
[hybrid](06-hybrid-search.md), [re-rank](07-re-ranking.md),
[prompt](12-prompt-engineering.md). "Production" is about wrapping them in the
operational concerns below.

## Caching — the biggest cheap win

Three **app-level** caches, each cutting latency *and* API cost:

- **Embedding cache** — identical text → reuse its vector, skip the embed call.
- **Retrieval cache** — repeated or near-identical queries → reuse the retrieved chunks.
- **Response cache** — FAQs → reuse the whole answer. Ideal for docs/support, where
  the same questions recur constantly.

And one **model-level** cache worth designing for:

- **Prompt (prefix) cache** — the provider caches the model's internal state (its **KV
  cache**) for a repeated prompt **prefix**, so tokens it has already "read" aren't
  re-processed on the next call. If every RAG request starts with the same long system
  prompt + rules, that fixed prefix is billed/processed once and reused — much cheaper
  and faster on the repeated part. **Practical tip:** order the prompt **stable → variable**
  (system prompt and format rules first, then the retrieved chunks, then the question)
  so the cacheable prefix is as long as possible.

## Guardrails

- **Input** — block prompt injection, malicious or out-of-scope requests, malformed input.
- **Output** — validate JSON schema, strip hallucinated fields, check citations exist,
  redact sensitive info — *before* returning to the user.

## Reducing hallucinations

You can't eliminate them, but you stack defenses (most are other notes):

- Better **retrieval / chunking / re-ranking** → the right facts are actually present.
- A grounding **system prompt** — "only from the docs, say I don't know"
  ([note 12](12-prompt-engineering.md)).
- **Citations** → answers are checkable.
- **Output validation** → catch unsupported claims before the user sees them.

## Structured outputs

Have the LLM return JSON, not prose, when the answer feeds software:

```json
{ "category": "refund", "confidence": 0.94, "answer": "…", "sources": ["DOC 1"] }
```

Easier to validate, automate, and route in agent workflows.

## Observability — know *why*

Log every stage: query → retrieved chunks → prompt → response → eval. When an answer
is wrong, the trace tells you whether retrieval missed or the LLM slipped. Tools like
**Phoenix (Arize)** are "Datadog / Grafana for LLM apps" — inspect retrieved chunks,
prompts, latency, hallucination signals, compare experiments. Track over time:
latency, cost, token usage, cache-hit rate, retrieval quality, satisfaction, errors.

## Cost & model selection

**Use the smallest model that can do each job.** Routing / classification / rewrite →
small fast model; final hard reasoning → large model; embeddings → a right-sized
embedding model. Plus: retrieve fewer chunks, cap context size, stream responses.

## Multimodal (a note on scope)

Knowledge isn't only text. Systems increasingly retrieve **images, tables, charts, PDF
pages** and pass them to a **multimodal LLM**. Non-text inputs are first converted
(OCR / layout analysis, or a vision encoder) into something the model can reason over.
Useful when the answer lives in a figure or table plain text can't capture.

**The key insight: the RAG logic doesn't change.** Only the *encoder* differs — an
image goes through a vision encoder, text through a text encoder — but each is turned
into a **vector**, and (given a shared embedding space) once you have vectors the rest
is identical: index them, find the nearest to the query, feed the top hits to the
model. `chunk → embed → retrieve → generate` is the *same pipeline* whether a "chunk"
is a paragraph, a table, or an image. Multimodal RAG is mostly "swap the encoder" — the
retrieval machinery you built for text carries over unchanged.

> For the *multi-agent* side of production systems — routers, tool use, loops — see
> [Agentic RAG](14-agentic-rag.md).

## Key takeaways

- Production RAG = a **modular pipeline**; every stage trades **quality ↔ latency ↔ cost**.
- **Cache** embeddings / retrieval / responses for the cheapest big win.
- **Guardrails** on input (injection) and output (schema, citations, PII).
- Fight hallucination with retrieval quality + grounding prompt + citations + validation.
- **Observe** every stage (Phoenix / Arize) so failures are debuggable.
- Use the **smallest model per task**; retrieve only what you need.

---

**In this project:** `learning_rag` is a *learning* build, not a production system —
but you can see the seams. Retrieval is already **modular** (swap TF-IDF / BM25 /
semantic / hybrid behind one interface), the
[eval harness](11-retrieval-evaluation-metrics.md) is the offline-quality half of
observability, and `Logger` traces each search stage. The production leap would be
adding caching, a generation step with guardrails, and per-stage monitoring on top.
