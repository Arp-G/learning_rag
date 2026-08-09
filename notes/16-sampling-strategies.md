# Sampling Strategies — temperature, top-k, top-p

> **TL;DR** — At each step an LLM outputs a *probability* for every possible next
> token; **sampling** is how you pick one. **Greedy** always takes the top token
> (deterministic). **Temperature** sharpens (<1, safer) or flattens (>1, wilder) the
> distribution. **Top-k** / **top-p** trim the candidate pool before sampling. For RAG
> you want **low temperature** — factual, consistent, grounded answers.

## The setup: a distribution over the next token

An LLM doesn't "write words" — at every position it predicts how likely each token is
to come next:

```
"The capital of France is ___"
   Paris  0.82
   London 0.06
   Berlin 0.03
   Rome   0.02   …
```

**Sampling** is the rule that turns that distribution into one chosen token. Different
rules → different behavior, from robotic-and-repetitive to creative-and-risky.

## Greedy decoding

Always pick the single highest-probability token.

- ✅ Deterministic, fast, predictable.
- ❌ Can be flat and repetitive — even loop ("very very very…").
- **Best for:** classification, extraction, structured output — anywhere you want *the*
  answer, not a creative one.

## Temperature — the risk dial

Temperature reshapes the distribution *before* sampling:

```
low T (0.2) → sharpen         high T (1.5) → flatten
  Paris  0.96                   Paris  0.45
  London 0.02                   London 0.20
  Berlin 0.01                   Berlin 0.15
(safe, focused)               (diverse, risky)
```

| temperature | behavior |
|---|---|
| 0.0 | deterministic (≈ greedy) |
| 0.2–0.4 | accurate, focused |
| 0.7 | balanced |
| 1.0+ | creative / diverse |

Mental model: **how willing is the model to take a risk?** Low = play it safe; high =
gamble on less-likely words.

## Top-k — keep the k best

Before sampling, discard everything except the **k** most likely tokens.

```
top-k = 3  →  keep {Paris, London, Berlin}, then sample among those
```

- ✅ Blocks bizarre, very-unlikely tokens.
- ❌ **Fixed** k ignores context — sometimes 3 good options exist, sometimes 30.

## Top-p (nucleus) — keep the top probability mass

Instead of a fixed count, keep the smallest set of tokens whose probabilities **add up
to p**, then sample from those.

```
Paris 0.60, London 0.20, Berlin 0.10, Rome 0.05, Madrid 0.03
top-p = 0.9 → keep {Paris, London, Berlin}   (0.60 + 0.20 + 0.10 = 0.90)
```

- ✅ **Adaptive**: when the model is confident the nucleus is tiny; when unsure it
  widens. Generally preferred over top-k.

| top-k | top-p |
|---|---|
| fixed number of tokens | variable — by probability mass |
| simple | adaptive to confidence |

## Two more knobs (they edit the *logits* directly)

Temperature / top-k / top-p reshape the *whole* distribution. These two instead nudge
**specific tokens' logits** — the raw pre-softmax scores — before softmax turns them
into probabilities.

- **Logit bias** — add a fixed number to chosen tokens' logits: `logit += bias`. A big
  positive bias makes a token much more likely; a large negative one (e.g. `−100`)
  drives its probability to ≈ 0 after softmax, effectively **banning** it. Use it to
  force or forbid specific words or formats.
- **Repetition penalty** — discourage tokens that already appeared, so the model stops
  looping ("very very very"). Two common shapes, both editing seen tokens' logits:
  - *Multiplicative* (`repetition_penalty` `r > 1`): divide a seen token's logit by `r`,
    shrinking its score.
  - *Additive* (OpenAI-style): subtract a flat **presence penalty** for any token seen
    at least once, plus a **frequency penalty** scaled by *how often* it appeared —
    `logit −= presence + frequency × count`.

  Either way, already-used tokens get a lower score → the next pick leans toward fresh
  words. Good for long-form writing and summarization.

## Key takeaways

- The model outputs a **distribution**; sampling picks the next token from it.
- **Greedy** = always the top token (deterministic).
- **Temperature** sharpens (low) or flattens (high) — the randomness dial.
- **Top-k** (fixed count) and **top-p** (probability mass, adaptive) trim candidates.
- **RAG → low temperature** for factual, repeatable, grounded answers.
