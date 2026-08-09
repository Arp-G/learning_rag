# LLM Characteristics & Benchmarks — picking (and running) a model

> **TL;DR** — Choosing an LLM means balancing **quality, cost, latency, context
> window**, and a few model properties: **size**, **training cutoff**, whether it's a
> **reasoning** model, and **where it runs** (hosted API vs local + quantization).
> Benchmarks (automated, human, LLM-judge) narrow the field, but they **saturate** and
> don't predict *your* workload — so always test on your own prompts and data.

## The characteristics that matter

- **Model size** (parameters) — small (~1–10B) = faster, cheaper; large (100B+) =
  better reasoning and instruction-following. *Bigger isn't always better* — pick the
  **smallest model that meets your quality bar** ([note 15](15-production-rag.md)'s cost
  lever).
- **Cost** — usually per **million tokens**, on input + output (+ reasoning tokens,
  below). Higher quality ≈ higher price.
- **Context window** — max tokens the model holds at once: system prompt + history +
  **retrieved chunks** + question + answer, all counted. Bigger windows fit more
  retrieved context but cost more and can slow down. (RAG's job is partly to *fit* the
  right context into this budget.)
- **Latency** — two numbers: **TTFT** (time to first token — how fast streaming starts)
  and **TPS** (tokens per second — how fast it continues).
- **Training cutoff** — the model knows nothing after this date *unless you supply it* —
  which is exactly what RAG (and web search) do. This is the whole reason RAG exists for
  fresh knowledge ([note 01](01-rag-vs-fine-tuning.md)).

## Reasoning models (a newer characteristic)

Standard chat models answer in one pass. **Reasoning models** (OpenAI o-series, GPT-5
reasoning, and similar) first do hidden **internal reasoning**, then answer:

```
question ─▶ [internal reasoning tokens] ─▶ final answer
```

- ✅ Much stronger on math, coding, planning, and multi-step / agentic tasks.
- ❌ Those **reasoning tokens** cost money and time — higher latency, bigger bill.
- **Prompt them differently:** give a clear goal + context + output format, and *let
  them reason*. Skip heavy few-shot and "think step by step" — that's built in now, and
  over-engineering the prompt can *hurt*. (Traditional models still benefit from
  few-shot + explicit [Chain of Thought](12-prompt-engineering.md).)

## Where it runs: hosted vs local

| | **Hosted API** (OpenAI, Anthropic…) | **Local** (Llama, Mistral…) |
|---|---|---|
| quality | highest (frontier) | usually lower |
| setup | none | you run the hardware |
| cost | per-token | hardware up front, cheap at scale |
| privacy | data leaves your box | **data stays in-house** |
| offline | no | yes |

**Quantization** makes local models practical: store weights at lower precision
(`FP32 → FP16 → INT8 → INT4`) to cut RAM/VRAM and speed inference, for a small quality
hit. A quantized 7–14B model runs comfortably on a consumer GPU; very aggressive
quantization (INT4 and below) trades away more accuracy.

## Measuring quality: three kinds of benchmark

No single benchmark captures everything. Three approaches, with different tradeoffs:

1. **Automated benchmarks** — code-graded on fixed datasets (**MMLU** knowledge,
   **HumanEval** coding, **GSM8K** math). ✅ fast, objective, reproducible. ❌ may not
   reflect real use, and a model can be "contaminated" by having seen the test set.
2. **Human evaluation** — people pick the better of two anonymous answers; ranked by
   **ELO** (e.g. **LMArena**). ✅ captures helpfulness, naturalness, writing quality —
   things code can't score. ❌ slow, expensive.
3. **LLM-as-a-judge** — an LLM scores answers (win rate, preference). ✅ cheap, fast,
   scalable. ❌ judges tend to favor their own model family's style. (The same tool used
   for RAG answer eval — [note 13](13-evaluating-llm-performance.md).)

**A good benchmark** is relevant to your task, hard enough to separate models,
reproducible, representative, and free of data contamination.

## Benchmark saturation

Over time, models cluster near the top of an old benchmark until it can't tell them
apart — **saturation** — so the field keeps inventing harder ones. Two consequences:
leaderboard gaps shrink (and mislead), and newer models mostly beat older ones on
*current* benchmarks.

> **The practical rule:** benchmarks *narrow* your candidates; they don't *choose* for
> you. Test finalists on **your prompts, your retrieval pipeline, your data, your
> metrics** — real-world fit beats leaderboard rank.

## Key takeaways

- Balance **quality / cost / latency / context window**; pick the **smallest model that
  clears your bar**.
- **Training cutoff** is why RAG exists for fresh facts; **context window** is the
  budget RAG fills.
- **Reasoning models** trade cost/latency for multi-step strength — and want *simpler*
  prompts.
- **Local + quantization** buys privacy / offline / control at some quality cost.
- Benchmarks (automated / human / LLM-judge) **saturate** — always **test on your own
  workload**.

---

**In this project:** the one model choice we make is the **embedding** model —
`text-embedding-3-small` (1536-dim), picked as the cheap, fit-for-purpose option over
the pricier `-large` ([Vectors & Embeddings](03-vectors-and-embeddings.md)). And the
whole eval harness embodies this note's closing rule: instead of trusting a
leaderboard, we **measure on our own data** (SciFact) with our own metrics — which is
how we know hybrid (0.757) actually beats semantic (0.71) *here*.
