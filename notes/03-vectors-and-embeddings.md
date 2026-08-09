# Vectors & Embeddings — turning meaning into numbers

> **TL;DR** — An **embedding** is a list of numbers (a vector) that a trained model
> assigns to a piece of text so that **similar meanings land close together** in
> space. That's the trick that lets search match *meaning* instead of spelling:
> "car" and "automobile" get nearby vectors even though they share no letters. We
> compare embeddings by **direction** (cosine similarity), not length.

## The intuition: meaning becomes a location

Keyword search (BM25) matches *spelling* — to it, "car" and "automobile" are just
different strings. Embeddings turn each text into a **point in space**, positioned
so that things that *mean* the same thing sit near each other:

```
              automobile
     car •      • vehicle
    truck •
                          • banana   • mango
```

Now "find similar meaning" becomes "find nearby points" — a geometry problem
computers are great at. All of semantic search is: embed the query, then find the
document points closest to it.

(Quick vocabulary — [vector, embedding, sparse vs dense](glossary.md#representing-text-as-numbers) are each
defined once in the glossary; here we build the intuition behind them.)

## Why do the numbers capture meaning?

Nobody hand-assigns these coordinates. The model **learns** them from millions of
examples using **contrastive learning** — a fancy name for a simple loop:

- Take two texts that *mean* similar things ("good morning" / "hello") → **pull
  their vectors together**.
- Take two that don't ("good morning" / "broken engine") → **push them apart**.
- Repeat millions of times, adjusting the model a hair each round.

```
text ─▶ model ─▶ vector ─▶ compare similar/different pairs ─▶ nudge weights ─▶ repeat
```

No one ever tells the model what "dog" *means*. After enough pulls and pushes,
`dog`, `puppy`, `wolf` end up clustered while `pizza`, `river`, `laptop` drift
elsewhere. **Meaning emerges from the geometry.**

## What the dimensions are

A real embedding has hundreds to thousands of numbers (384, 768, 1536, 3072…).
Think of each dimension as a **hidden feature** the model invented for itself —
loosely, things like "animal-ness", "is-it-food", "sentiment", "medical-ness". You
can't actually read them (they're abstract and tangled together), but the picture
holds:

> More dimensions → more room to separate ideas → finer distinctions captured.

You can't visualize 1536-D, but the 2-D intuition ("near = similar") carries over
unchanged.

### Directions carry meaning (vector arithmetic)

Here's the striking consequence: because meaning lives in *directions*, you can do
**arithmetic** on vectors and land somewhere meaningful. The famous word-embedding
result:

```
king − man + woman  ≈  queen
```

Read it as: start at *king*, subtract the "male" direction, add the "female"
direction → you arrive right next to *queen*. That `(woman − man)` step is a
reusable "gender" direction (`uncle − man + woman ≈ aunt`).

The same works for other hidden attributes. Say `(elephant − rat)` roughly captures
"bigness". Then:

```
kitten + (elephant − rat)  ≈  a large, cat-like thing  →  lands near "tiger"
```

Nobody *programmed* a "size" or "gender" axis — those directions **emerge** from
training. That's the real payoff of the dimensions being meaningful: no single
dimension is human-readable, yet consistent *directions* through the space are.

> Caveat: this clean arithmetic is strongest for classic *word* embeddings (word2vec,
> GloVe). Modern *sentence* embeddings like ours don't do it as tidily — but the
> intuition, **meaning is encoded as direction**, is exactly why cosine similarity works.

## Direction, not length

A vector has a **direction** and a **length (magnitude)**. For meaning, only
direction matters:

```
[10, 10]   and   [100, 100]   →   same direction, 10× the length
```

These should count as the *same meaning* — one text is just "louder" (longer, more
repetitive). So we compare the **angle** between vectors and ignore length. That
comparison is **cosine similarity**.

## Cosine similarity (the default)

```
cosine(A, B) = (A · B) / (‖A‖ · ‖B‖)
```

The top, `A · B`, is the **dot product**; dividing by both **lengths** (`‖A‖ · ‖B‖`)
cancels magnitude, leaving only the angle.

| value | angle | meaning |
|:---:|:---:|---|
| **+1** | 0° | same direction → same meaning |
| **0** | 90° | perpendicular → unrelated |
| **−1** | 180° | opposite direction → opposite meaning |

Dividing by both lengths is what "removes magnitude": it collapses any vector to a
pure direction. So `[10,10]` vs `[100,100]` → cosine = **1**, correctly "identical".

*Tiny worked example.* `A = [2, 0]`, `B = [1, 1]`:
`A·B = 2·1 + 0·1 = 2`, `‖A‖ = 2`, `‖B‖ = √2`. cosine = `2 / (2·√2) ≈ 0.71` — a 45°
angle. Related, but not identical.

## Cosine vs dot product (and a correction)

The **dot product** `A·B = A₁B₁ + A₂B₂ + …` measures direction **and** length, so a
longer vector scores higher even when pointing the same way. Cosine is just the dot
product **normalized** — divided by the lengths — so only direction survives.

> ⚠️ Careful with a common slip: for *opposite* directions the **cosine** is −1, but
> the **dot product** is `−‖A‖·‖B‖` (some negative number), **not** literally −1.
> The tidy −1 / 0 / +1 range belongs to cosine alone. Dot product equals cosine
> *only when both vectors are unit length* (normalized to length 1).

Handy fact: most embedding models return **already-normalized** vectors (length 1).
Then dot product *equals* cosine — which is why libraries often use the faster dot
product under the hood.

## When it shines — and its blind spot

- ✅ Matches **meaning**: synonyms, paraphrases, related concepts. With the right
  model, even across languages or across text↔image.
- ❌ Can miss **exact** rare tokens — an error code, a product SKU, a surname — where
  the literal *string* is the point. Blurring everything into "meaning" loses those.
  That's the mirror image of BM25's weakness, and exactly why
  [Hybrid Search](06-hybrid-search.md) runs both.
- ❌ **Opaque**: unlike BM25 you can't point at "which word matched" — the match
  lives inside 1536 numbers.

## Key takeaways

- An **embedding** = a trained model's numeric fingerprint of *meaning*; similar
  meaning → nearby vector.
- Meaning is **learned** by pulling similar texts together and pushing different
  ones apart (contrastive learning).
- Compare by **direction** → **cosine similarity** (+1 same, 0 unrelated, −1 opposite).
- Cosine = **normalized dot product**; the two agree only for unit-length vectors.
- Great for synonyms and paraphrase; weak on exact rare tokens → pair it with
  keyword search.

---

**In this project:** chunks and queries are embedded with OpenAI
`text-embedding-3-small` (**1536** dimensions) and stored in a pgvector `vector`
column. Similarity is cosine, computed in SQL as `1 - (embedding <=> $1)` (pgvector's
`<=>` returns cosine *distance*, so we flip it to a score). Next: how that search
actually runs → [Semantic Search](04-semantic-search.md), and how it stays fast at
scale → [Searching Algorithms](05-searching-algorithms.md).
