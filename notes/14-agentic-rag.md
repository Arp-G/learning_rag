# Agentic RAG — multi-step, tool-using retrieval

> **TL;DR** — Classic RAG is one shot: retrieve once, generate once. **Agentic RAG**
> puts an LLM in a **loop** where it *decides* what to do — rewrite the query, pick a
> tool or knowledge base, retrieve again, check its own answer, retry. You trade
> simplicity and latency for the ability to handle complex, multi-step questions a
> single retrieve-then-generate pass can't.

## The shift: from pipeline to loop

```
classic RAG:   query ─▶ retrieve ─▶ generate ─▶ answer          (fixed, one pass)

agentic RAG:   query ─▶ ┌─ plan ──▶ retrieve / call a tool ─┐
                        └─◀ evaluate ◀── generate ◀─────────┘   (loop until good)
```

The core change: the model isn't a fixed step in a pipeline — it's a
**decision-maker** that plans actions, calls tools, inspects results, and chooses what
to do next. "Should I search? which source? is this answer good enough, or retry?"
become *model* decisions instead of hardcoded ones.

## Why bother?

Some questions need more than one retrieval:

- **Multi-hop** — "What did the CEO of the company that makes X say about Y?" chains
  two lookups.
- **Multi-source** — pull from docs *and* a SQL table *and* web search, then combine.
- **Self-correction** — draft, notice a claim is unsupported, retrieve more, fix it.
- **Tool use** — a calculator, a code runner, an API the text simply can't answer.

A single prompt can't do these; a loop that retrieves–reasons–retrieves can.

## The four workflow patterns

| pattern | shape | good for |
|---|---|---|
| **Sequential** | A → B → C, fixed order | simple, predictable chains (parse → retrieve → generate → cite) |
| **Conditional** | a **router** picks the path | "is this an FAQ, a doc search, or a calculation?" |
| **Iterative** | generate → evaluate → retry until OK | self-correction, validation, reflection loops |
| **Parallel** | fan out to N agents, then merge | independent sub-tasks (search + SQL + calc) at once |

Real systems mix these — e.g. a router (conditional) that dispatches to a parallel
fan-out, each branch a short sequential chain with an iterative check.

## Multi-model: right-size each step

Because the work is split into steps, you can use a **different model per step** — the
cheapest one that can do that job:

```
routing / classification    → small, fast model
generation / hard reasoning → large model
evaluation, citations       → small–medium model
```

Using a frontier model only where it's actually needed cuts cost and latency a lot.

## Orchestration

Something has to coordinate the loop — call models and tools, pass state between
steps, retry on failure, validate, combine results. That's the **orchestration
layer**. Frameworks (LangGraph, CrewAI, OpenAI Agents SDK) help, it's just code so
we can also hand-roll it.

## The tradeoff

Agentic isn't automatically better. More LLM calls = **more latency and cost**; more
moving parts = **more ways to fail**. Reach for it when the task genuinely needs
multi-step reasoning or tools — not for a question one hybrid retrieval + one
generation would already answer.

## Key takeaways

- Agentic RAG = an LLM in a **loop**, deciding what to retrieve / which tool / whether to retry.
- Enables multi-hop, multi-source, self-correcting, tool-using answers.
- Patterns: **sequential, conditional, iterative, parallel** — usually combined.
- Use a **small model per cheap step**, a big one only for hard generation.
- Costs latency, money, and complexity — use it only when the task needs it.
