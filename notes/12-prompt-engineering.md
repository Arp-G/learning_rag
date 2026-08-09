# Prompt Engineering — the prompt you build around the passages

> **TL;DR** — In RAG the prompt is much more than the user's question. You assemble
> an **augmented prompt**: a **system prompt** (behavior + grounding rules) +
> **conversation history** + **retrieved chunks** + the **question**. The rules that
> matter most for RAG: *answer only from the retrieved text, cite sources, and say "I
> don't know" when it isn't there* — that's what turns retrieval into a grounded,
> non-hallucinating answer.

## Chat messages: the shape of a prompt

Modern models take a list of role-tagged messages, not one string:

```json
[ {"role": "system",    "content": "You answer only from the provided documents."},
  {"role": "user",      "content": "What is the capital of Canada?"},
  {"role": "assistant", "content": "Ottawa."},
  {"role": "user",      "content": "Why was it chosen?"} ]
```

- **system** — behavior, rules, output format, tools. Sent with *every* request.
- **user** — the request.
- **assistant** — prior model replies; this is how multi-turn memory works.

## The RAG system prompt (where grounding lives)

The system prompt is where you make RAG *behave*. The high-value instructions:

```
You are a helpful assistant.
- Answer ONLY using the retrieved documents below.
- If the answer isn't in them, say you don't know — do not guess.
- Cite sources as [DOC 1], [DOC 2].
- Be concise.
```

Those four lines are most of what separates "grounded RAG" from "a chatbot that
sometimes makes things up." *Only from the documents* + *say I don't know* is the
core anti-hallucination lever; *cite* makes answers checkable.

## The augmented prompt

The final thing you send is the **augmented prompt** — the question *augmented* with
everything the model needs to answer well:

```
system prompt  +  conversation history  +  retrieved chunks  +  user question
                                                                    ↓
                                                          grounded answer
```

Production systems build this from a **template** (a fixed skeleton with slots filled
per request) so prompts stay consistent, maintainable, and easy to extend.

## In-context learning: teach by example

Instead of *describing* the format you want, *show* it — examples right in the prompt:

```
Q: How do I reset my password?
A: Click "Forgot Password" on the login page.        ← the model copies this pattern
```

- **One-shot** = one example; **few-shot** = several. More examples → more
  consistency, but they eat context budget.
- **Dynamic few-shot** — instead of hardcoding examples, *retrieve* the most relevant
  ones for each query (same machinery as document retrieval) and inject those. Great
  for support and workflows where the right example depends on the question.

(This is why a model can "learn" a task with zero weight changes — it's all in the
prompt. More in [LLM Characteristics](17-llm-characteristics.md).)

## Chain of Thought — make it reason first

For multi-step questions, ask the model to **work through it step by step** before
answering, instead of committing to a final token immediately:

```
Q: A shirt is $40 with 25% off. Final price? Think step by step.
A: 25% of 40 = 10.  40 − 10 = 30.  Answer: $30.
```

Spelling out the reasoning ("Chain of Thought") reliably improves accuracy on math,
logic, and multi-hop questions — the model commits to intermediate steps instead of
guessing in one leap.

**Reasoning models** (o-series, GPT-5 reasoning) do this *internally* and want the
opposite treatment: a clear goal and context, **not** big few-shot blocks or "think
step by step" (it's built in — over-prompting can hurt). Which style fits is a
property of the model → [LLM Characteristics](17-llm-characteristics.md).

## Key takeaways

- The prompt is a list of **system / user / assistant** messages; the system prompt
  sets behavior and rides along with every request.
- **Augmented prompt** = system + history + retrieved chunks + question, from a template.
- RAG's grounding lives in the system prompt: *only from the docs, cite, say "I don't know."*
- **Few-shot** teaches format; **dynamic few-shot** retrieves the best examples per query.
