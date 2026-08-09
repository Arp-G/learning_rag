# Evaluating LLM Performance — grading the answer

> **TL;DR** — A RAG system has two halves to grade *separately*: the **retriever**
> (did it fetch the right docs — [note 11](11-retrieval-evaluation-metrics.md)) and
> the **generator** (did the LLM write a good answer *from* those docs). Answer
> quality is subjective, so it's usually scored by **another LLM ("LLM-as-a-judge")**.
> The two metrics that matter most: **faithfulness** (is the answer supported by the
> retrieved text — i.e. no hallucination) and **response relevancy** (does it actually
> answer the question).

## Two components, two evaluations

```
retriever ─▶ relevant docs ─▶ LLM ─▶ answer
└─ metrics: recall, precision,      └─ metrics: faithfulness, relevancy,
   MAP, MRR, NDCG (note 11)            citation quality (this note)
```

Grade them separately. If the answer is bad, you need to know whether **retrieval
missed** the doc (fix the retriever) or the **LLM ignored/misused** a doc it *was*
given (fix the prompt or model). One combined score hides which half broke.

## Why LLM-as-a-judge?

"Is this answer faithful / relevant / well-cited?" has no regex. So you hand the
answer — plus the question and the retrieved docs — to a capable LLM and ask *it* to
score each quality. It's the only scalable way to grade open-ended text: a human
rater's judgment, automated. (Caveats: judges have biases and cost money; you still
spot-check against humans.)

## Faithfulness (the anti-hallucination metric)

> Is every claim in the answer supported by the retrieved documents?

```
faithfulness = (supported claims) / (total claims)
```

How a judge computes it: extract each factual claim from the answer, check each one
against the retrieved context, count the fraction supported. Low faithfulness = the
model invented things that aren't in the docs — the exact failure RAG exists to
prevent. This is *the* metric to watch.

## Response relevancy

> Does the answer actually address the question? (Not *is it true* — just *is it on
> point*.)

A neat way to measure it: have an LLM read the *answer* and generate the questions it
seems to answer; embed those and compare (cosine) to the *original* question. High
similarity → on-topic. It deliberately ignores correctness — a confident but
off-topic answer scores low even if factually true.

## Beyond single metrics: RAGAS & system-level

- **RAGAS** (Retrieval-Augmented Generation Assessment) is a popular framework
  bundling these LLM-judged metrics — faithfulness, response relevancy, context
  precision/recall, citation quality — so you don't hand-roll each judge.
- **System-level** signals catch what offline metrics miss: 👍/👎 feedback, A/B tests,
  task-success rate, human review, production analytics. These measure the thing you
  actually care about — real users getting real answers.

## Key takeaways

- Grade **retriever** and **generator** separately, or you can't tell which broke.
- Open-ended answer quality → **LLM-as-a-judge**.
- **Faithfulness** = fraction of answer claims supported by the docs → hallucination check.
- **Response relevancy** = does it answer the question (not: is it true).
- Pair offline metrics (RAGAS) with real-world signals (feedback, A/B).
