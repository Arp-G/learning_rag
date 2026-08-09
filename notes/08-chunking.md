# Chunking — splitting documents into passages

> **TL;DR** — You embed and retrieve **chunks** (small passages), not whole
> documents, because one vector for a long document averages all its topics into
> mush. Split into pieces small enough to be *about one thing*, big enough to stand
> alone, and **overlap** them so a sentence isn't sliced in half at a boundary.
> Common default: ~200–500 tokens with ~20–50 token overlap — then measure on your data.

## Why chunk at all?

Two reasons, one intuition each:

1. **One vector can't represent many topics.** Embed a 100-page doc covering AI,
   databases, networking, and security into a *single* vector and you get the
   *average* of all four — close to none of them. A query about "database indexes"
   matches it only weakly. Split by topic and each chunk's vector is *sharp*.
2. **The LLM wants the relevant paragraph, not the book.** RAG pastes retrieved text
   into the prompt; you want the focused passage that answers the question — not 50
   pages it has to wade through (and that blow the context window).

> Goal: retrieve the *relevant part* of a document, not the whole document.

## The size tradeoff

```
small chunks  ──────────────────────────────▶  large chunks
precise, sharp vector                          rich context
but may lose context                           but blurry, multi-topic vector
```

- **Too small** — "The Eiffel Tower" as its own chunk loses "…is located in Paris"
  from the next line. Precise but context-starved.
- **Too large** — a chunk covering restaurants *and* hotels *and* flights averages
  into one fuzzy vector that matches none of them sharply.

There's **no universal best size** — it depends on document type, query type,
embedding model, and the LLM's context window. Start around 200–500 tokens and
*evaluate*.

## Overlap: don't cut mid-thought

Adjacent chunks share a little text at the seam, so an idea split across a boundary
survives in at least one chunk:

```
no overlap:  […is located]  |  [in Paris and was built…]   ← "located in Paris" is severed
overlap:     […is located]  |  [Tower is located in Paris…] ← intact in chunk 2
```

A 20–50 token overlap cheaply prevents boundary information loss. The cost is a
little duplication (chunks aren't disjoint).

## Basic strategies

| strategy | how | trade |
|---|---|---|
| **Fixed-size** | cut every N tokens/words | simple, fast; ignores structure (may split sentences) |
| **Sentence** | cut on sentence ends | respects language; sentence lengths vary a lot |
| **Paragraph** | one paragraph per chunk | good when a paragraph = one idea |
| **Document-aware** | cut on headings / sections / lists | most meaningful; needs structured input |

Rule of thumb: prefer **meaningful boundaries** (sentence / paragraph / section) over
arbitrary cuts whenever the document has structure to exploit. Smarter strategies →
[Advanced Chunking](09-advanced-chunking.md).

## Key takeaways

- Chunk *before* embedding; retrieve chunks, not whole documents.
- **Small** → precise but context-poor; **large** → context-rich but blurry vectors.
- **Overlap** (20–50 tokens) preserves context across boundaries.
- No universal size — start 200–500 tokens and evaluate on *your* data.

---

**In this project:** [`ingest/chunker.ex`](../lib/learning_rag/ingest/chunker.ex)
uses **overlapping word-window** chunking — fixed size in words, with overlap — the
simplest strategy that still protects boundaries. SciFact abstracts are short, so a
modest window keeps most abstracts to one or a few chunks. Retrieval scores chunks;
[eval](11-retrieval-evaluation-metrics.md) then collapses chunks back to their parent
document before grading.
