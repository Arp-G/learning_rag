# Retrieval Evaluation Metrics — Precision@K, Recall, MRR, MAP, NDCG

> **TL;DR** — To know if a retriever is good, compare its ranked results against a
> human **answer key** (which docs are relevant per query). **Precision** = of what I
> returned, how much was right; **Recall** = of all the right ones, how much I found;
> **MRR** = how high the *first* good result landed; **MAP** = are *all* the good ones
> near the top; **NDCG** = the same, but honoring *graded* relevance and discounting
> lower positions by a log. NDCG is the headline metric here (and what BEIR reports).

## What you need to evaluate

```
query  +  the retriever's ranked results  +  ground truth (qrels: which docs are relevant)
```

Every metric below is a different way of scoring the *ranked results* against the
*ground truth*. ([qrels / ground truth in the glossary](glossary.md#evaluation).) Each
scores **one** query; you then average over all queries.

## Precision & Recall — the base pair

Both count the same thing on top — the **hits** (relevant docs you actually
returned). They differ *only in the denominator*:

```
Precision  =  hits / (total you RETURNED)
Recall     =  hits / (total that EXIST)
```

- **Precision** divides by **what you returned** → "of what I showed, how much was
  right?" (few false alarms)
- **Recall** divides by **what exists** → "of everything relevant, how much did I
  find?" (few misses)

They **trade off**. Return 5 docs, all correct, when 100 relevant exist →
Precision = 5/5 = **100%**, Recall = 5/100 = **5%**. Great precision, terrible recall.

## @K — because retrievers return a top-K

Retrievers return a ranked top-K, so metrics are measured on the first K:

- **Precision@K** — of the top K, how many are relevant. Top-5 `[✓ ✓ ✗ ✓ ✗]` → 3/5 = **0.60**.
- **Recall@K** — of all relevant, how many landed in the top K. 6 of 8 relevant in the
  top-10 → **0.75**.

But @K precision/recall **ignore order within the K** — `[✓ ✓ ✗ ✗ ✗]` and
`[✗ ✗ ✗ ✓ ✓]` score the same. The next three metrics reward getting hits *higher up*.

## MRR — Mean Reciprocal Rank (how soon the first hit?)

**Reciprocal Rank (RR)** = `1 / (rank of the first relevant result)`. **MRR** is the
mean of RR across all queries.

```
first hit at rank 1  →  RR = 1/1 = 1.00
             rank 2  →  RR = 1/2 = 0.50
             rank 5  →  RR = 1/5 = 0.20
```

*Tiny example* — 3 queries, first hit at ranks 1, 3, 2:

```
MRR = (1/1 + 1/3 + 1/2) / 3 = (1.00 + 0.33 + 0.50) / 3 ≈ 0.61
```

Perfect when you care about the *single* best answer ("I'm feeling lucky"). It ignores
everything after the first hit.

## MAP — Mean Average Precision (are *all* the good ones near the top?)

Two steps:

1. **Average Precision (AP)** for one query — at each rank where a relevant doc sits,
   take Precision@that-rank; sum those and divide by the *total* number of relevant
   docs (so relevant docs you never found still drag it down).
2. **MAP** = the mean of AP across all queries.

*Tiny example* — 2 relevant docs total, found at ranks 1 and 3:

```
rank 1: 1 hit  in top 1  →  P@1 = 1/1 = 1.00
rank 3: 2 hits in top 3  →  P@3 = 2/3 = 0.67
AP = (1.00 + 0.67) / 2 relevant = 0.83
```

Hits earlier → higher AP. Unlike MRR, it cares about *every* relevant doc, not just
the first.

> **What "binary relevance" means:** MAP — and precision, recall, MRR — treat every
> doc as simply **relevant or not**, a 1 or a 0. There's no "very relevant" vs
> "slightly relevant": a barely-useful doc and a perfect one count exactly the same.
> NDCG is the one metric that drops this assumption.

## NDCG — Normalized Discounted Cumulative Gain (the headline)

The richest ranking metric, and the one this project reports. It adds two ideas on top
of "did we find relevant docs?".

**1. Graded relevance → a "gain".** Instead of relevant/not, each doc has a *grade* of
how relevant it is (0 = irrelevant … 3 = perfect). The grade becomes a **gain** — how
much usefulness that doc adds:

| grade | 0 | 1 | 2 | 3 |
|---|:--:|:--:|:--:|:--:|
| **gain** = `2^grade − 1` | 0 | 1 | 3 | 7 |

Why `2^grade − 1` instead of just the grade? The exponential makes top grades count
*disproportionately* more — one "perfect" (gain 7) outweighs three "related" docs
(1+1+1 = 3). Finding one great doc beats finding several so-so ones. (With **binary**
grades the gain is just 0 or 1 — the exponential only bites when real grades exist,
which is why NDCG collapses to a position-only score on binary data like SciFact.)

**2. Position discount.** A hit high up is worth more than the same hit lower down.
Divide each gain by `log2(position + 1)`, which grows slowly, so lower ranks are
gently penalized:

| rank (position) | 1 | 2 | 3 | 4 |
|---|:--:|:--:|:--:|:--:|
| divisor `log2(rank + 1)` | 1.00 | 1.58 | 2.00 | 2.32 |

**DCG@K** (Discounted Cumulative Gain) simply adds up those discounted gains over the
top K:

```
DCG@K = gain(rank 1)/log2(2) + gain(rank 2)/log2(3) + gain(rank 3)/log2(4) + ...
```

Then **normalize**: divide by the DCG of the *best possible* ordering — **IDCG**
("ideal" DCG: the same relevant docs sorted by grade, highest first). That turns it
into a clean **0…1**, comparable across queries with different numbers of relevant docs:

```
NDCG@K = DCG@K / IDCG@K      →  1.0 = ranked as well as possible, 0 = found nothing
```

*Worked example* — top-3 grades `[2, 0, 1]` (two relevant docs, grades 2 and 1):

```
gains of what we returned:  [3, 0, 1]
DCG   = 3/1.00 + 0/1.58 + 1/2.00  = 3.50     ← what we got
IDCG  = 3/1.00 + 1/1.58           = 3.63     ← best order would be grades [2, 1]
NDCG  = 3.50 / 3.63               ≈ 0.96
```

0.96, not 1.0, because the grade-1 doc sat at rank 3 instead of rank 2 — the position
discount docked us slightly.

## Which metric when?

| metric | full name | answers | relevance |
|---|---|---|:--:|
| Precision@K | — | of top K, how many right? | binary |
| Recall@K | — | of all relevant, how many in top K? | binary |
| MRR | Mean Reciprocal Rank | how high is the *first* hit? | binary |
| MAP | Mean Average Precision | are *all* hits near the top? | binary |
| **NDCG@K** | Normalized Discounted Cumulative Gain | best-ordered, graded + discounted | **graded** |

A strong retriever wants **high recall** (finds them), **high precision** (few duds),
and **high MAP / NDCG** (best first) — no single number tells the whole story.

## Key takeaways

- Metrics compare ranked results to a **ground-truth answer key** (qrels).
- **Precision vs recall**: same hits on top, different denominator (returned vs
  exists); they trade off. `@K` ignores order within the K.
- **MRR** (first hit's position) and **MAP** (all hits near the top) use **binary**
  relevance — relevant or not.
- **NDCG** = graded **gain** (`2^grade − 1`) with a **log position discount**,
  normalized to 0…1 — the richest, and our headline.

---

**In this project:** [`eval/metrics.ex`](../lib/learning_rag/eval/metrics.ex)
implements all of these — each is a plain function with doctests, using exactly the
`gain = 2^grade − 1` DCG above. The
[runner](../lib/learning_rag/eval/runner.ex) retrieves a pool of chunks, collapses them
to parent documents, and grades the ranking against SciFact's qrels. SciFact's grades
are all **1** (binary), so gain is always 1 and NDCG here rewards *position* alone.
**NDCG@10** is the headline: TF-IDF 0.54 → BM25 0.69 → semantic 0.71 → hybrid 0.757.
Run it: `mix rag.eval --scorer hybrid`.
