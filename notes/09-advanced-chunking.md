# Advanced Chunking — smarter splitting

> **TL;DR** — Basic size-based chunking splits related text and mixes topics. Smarter
> strategies cut on *meaning*: **recursive** (try big separators, recurse if too big —
> a great default), **semantic** (cut where the topic shifts), **LLM-based** (let a
> model place the cuts), and **parent-child** (retrieve on small precise chunks, feed
> the big surrounding chunk to the LLM). Add **metadata** so you can filter.

## The problem with basic chunking

Fixed-size and even sentence/paragraph cuts can still split one idea across two
chunks, or jam two topics into one. Advanced strategies aim for chunks that are each
**about one thing** — which keeps their embeddings sharp and retrieval accurate.

## Recursive chunking (the strong default)

Split using a **hierarchy of separators**, largest first; if a piece is still too
big, recurse with the next-smaller separator:

```
split on headings ─▶ still too big? ─▶ paragraphs ─▶ still too big? ─▶ sentences ─▶ words
```

You get chunks that respect the document's natural structure *and* fit a size
budget. This is the general-purpose default (it's what LangChain's
`RecursiveCharacterTextSplitter` does).

## Semantic chunking (cut where meaning shifts)

Instead of a size rule, walk the sentences and start a new chunk when the **topic
changes** — detected by a drop in embedding similarity between consecutive sentences:

```
ML  ML  ML  |  DB  DB  DB      →   chunk 1 = the ML run, chunk 2 = the DB run
           ↑ similarity drops here → cut
```

- ✅ Great topic coherence → meaningful embeddings.
- ❌ More expensive (you embed *while* chunking).

## LLM-based (context-aware) chunking

Hand the document to an LLM and let it place boundaries by *understanding* it — e.g.
splitting an annual report cleanly into "Financial Summary" and "Risk Factors"
sections regardless of their length.

- ✅ Highest-quality chunks; handles messy, complex documents.
- ❌ Slow, costs money, needs an LLM call per document.

## Parent-child (retrieve small, return big)

This one directly resolves the **precision-vs-context tension** from
[Chunking](08-chunking.md).

**How you build it:** split each document into big **parent** chunks (say, whole
sections), then split *each parent* into small **child** chunks (a few sentences).
Every child stores a pointer to its parent. You **embed and index only the children**;
the parents just sit in storage, keyed by id.

**At query time:**

```
1. match a small CHILD chunk        → sharp, precise retrieval
2. follow its pointer to the parent
3. hand the LLM the PARENT chunk     → full surrounding context
```

So you *search* on the sharp little passage but *feed the model* the whole section
around it — best of both. (Several children often point to the same parent, so you
de-duplicate parents before sending them on.)

## Metadata-aware chunking

Attach fields to each chunk — `title`, `section`, `author`, `date`, `source`. Later
used for [metadata filtering](06-hybrid-search.md), better prompts, and structured
queries. Cheap to add, pays off everywhere.

## Which strategy?

| strategy | best for |
|---|---|
| Fixed-size | simple baseline |
| **Recursive** | general-purpose documents (strong default) |
| Semantic | topic-heavy documents |
| LLM-based | high-quality production RAG |
| Parent-child | long documents needing context |
| Metadata-aware | enterprise / filtered search |

## Key takeaways

- Chunk by **meaning**, not just size.
- **Recursive** is the best default; **semantic** / **LLM** improve coherence at a cost.
- **Parent-child** gives precise retrieval *and* rich context — a very useful pattern.
- **Metadata** on chunks unlocks filtering and better prompts.

---

**In this project:** we use plain overlapping word-window chunking
([`chunker.ex`](../lib/learning_rag/ingest/chunker.ex)) — deliberately the simple
baseline, since SciFact abstracts are short and single-topic. On longer, structured
documents, **recursive** + **parent-child** would be the first upgrades — and the
existing `documents → chunks` split is already a parent-child skeleton (every chunk
knows its parent document).
