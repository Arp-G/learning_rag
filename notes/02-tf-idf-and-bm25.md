# TF-IDF & BM25 — keyword (sparse) retrieval

> **TL;DR** — Rank a document for a query by scoring each shared word: a word
> counts for more if it's **frequent in this document** but **rare across all
> documents**. BM25 is the same idea with two fixes — repeats give diminishing
> returns, and long documents get a penalty. It's a fast, strong baseline that
> matches *exact* words but is blind to synonyms.

## The intuition

To tell what a document is *about*, you look at its words — but not every word is
a useful clue. A word is a strong clue only when **two things are true at once**:

1. **It appears a lot in that document.** A film review that says "Nolan" five
   times is probably about a Nolan movie. → **term frequency (TF)**: how often, *here*.
2. **It's rare across all documents.** The word "movie" is in *every* review, so
   counting it tells you nothing about *which* review. Only words that are unusual
   overall actually point somewhere. → **inverse document frequency (IDF)**: how
   rare, *overall*.

| word (across a pile of movie reviews) | frequent in this review? | in *every* review? | useful clue? |
|---|:---:|:---:|---|
| `movie` | yes | yes | ✗ no signal — everyone has it |
| `Nolan` | yes | no | ✓ distinctive — points to *this* one |

So a word scores high for a document when it's **frequent here _and_ rare
everywhere else**. TF-IDF is exactly that, turned into a number: multiply "how
often here" (TF) by "how rare overall" (IDF), then add it up over the query's words.

## TF — term frequency (count it *here*)

```
tf(word, doc) = number of times the word appears in the doc
```

Sometimes divided by the document's length so long docs don't get a free boost.

*Example* — doc = `"cat sat on the cat mat"` (6 words). `cat` appears twice →
tf = 2 (or 2/6 ≈ 0.33 if you normalize by length).

## IDF — inverse document frequency (how *rare* is it, overall?)

```
idf(word) = ln( N / df )
```

`N` = total number of documents; `df` = how many documents contain the word.

Rare word → small `df` → **big** idf. A word in *every* document → `df = N` →
`idf = ln(1) = 0`, so it adds nothing. That's the point: common words are dead weight.

**Why the `ln` (log)?** Without it, a word in 1-in-a-million documents would get a
score a million times bigger than a common one and drown out everything else. The
log squashes that range: rarity still helps a lot, but not insanely.

*Example* — corpus of `N = 1000` documents:

| word | in how many docs (df) | idf = ln(1000/df) | signal |
|------|----:|----:|---|
| the | 990 | ≈ 0.01 | ~useless |
| jaguar | 5 | ≈ 5.3 | strong |

## TF-IDF = TF × IDF

Score a document for a query = **sum, over each query word, of `tf × idf`**.

*Worked example.* Three tiny documents, query = `"cat dog"`:

| doc | text | tf(cat) | tf(dog) |
|-----|------|:---:|:---:|
| D1 | `cat cat dog` | 2 | 1 |
| D2 | `cat fish fish` | 1 | 0 |
| D3 | `dog dog bird` | 0 | 2 |

`N = 3`. `df(cat) = 2` (D1, D2), `df(dog) = 2` (D1, D3), so
`idf(cat) = idf(dog) = ln(3/2) ≈ 0.405`.

| doc | score = Σ tf·idf | |
|-----|---|---|
| **D1** | 2(0.405) + 1(0.405) = **1.22** | has *both* words → wins |
| **D3** | 2(0.405) = **0.81** | two "dog"s |
| **D2** | 1(0.405) = **0.41** | one "cat" |

Ranking: **D1 > D3 > D2**. Exactly what you'd want. (This is the same example the
project's test checks by hand — see [`sparse_search_test.exs`](../test/learning_rag/search/sparse_search_test.exs).)

## Where TF-IDF falls short → BM25

Raw TF-IDF has two weaknesses:

1. **Counts grow linearly.** A document with "apple" ×50 scores 50× a document
   with it ×1. But is it really *50 times* more about apples? No — after a few
   mentions you already know it's about apples. Repeats should **saturate**.
2. **Long documents cheat.** A long document repeats words just by being long, so
   it piles up `tf` without being more relevant.

**BM25** is TF-IDF with a fix for each, controlled by two knobs:

- **`k1` — saturation.** The count's contribution climbs toward a **ceiling**
  instead of forever. The 1st mention matters a lot; the 20th barely moves it.
  *(typical `k1 ≈ 1.2`)*
- **`b` — length normalization.** Discount documents longer than average.
  `b = 0` ignores length entirely; `b = 1` applies the full penalty.
  *(typical `b ≈ 0.75`)*

### The formula (don't memorize — read the shape)

```
score(D, Q) = Σ  idf(w) · tf·(k1 + 1) / ( tf + k1·(1 − b + b·|D|/avgdl) )
              w∈Q
```

- `idf` — same "how rare" as before (BM25 uses a variant, `ln(1 + (N−df+0.5)/(df+0.5))`,
  that stays positive).
- the fraction — "how often", but **saturating** (via `k1`) and **length-adjusted**
  (via `b`). `|D|` = this document's length, `avgdl` = the average document length.

Hold onto three words: **rarity × saturating-count × length-penalty**.

### Saturation, made concrete

Here's the "how often" part as the count climbs (with `k1 = 1.2`, length ignored).
Watch it flatten toward a ceiling of `k1 + 1 = 2.2`:

| count (tf) | 1 | 2 | 4 | 10 | 50 | → ∞ |
|-----------|--:|--:|--:|--:|--:|--:|
| contribution | 1.00 | 1.38 | 1.69 | 1.96 | 2.15 | 2.20 |

Going 1 → 2 adds a lot; 10 → 50 adds almost nothing. That's the "you already got
the point" effect TF-IDF was missing.

## The sparse-vector view (bridge to embeddings)

Give every word in the vocabulary its own dimension. A document becomes one giant
vector: mostly **zeros** (it uses only a few hundred of ~30,000 words) with a
weight on the words it does contain. That's a **sparse vector**.

- A BM25 score is essentially a **dot product** between the query's sparse vector
  and the document's — only the shared words contribute.
- That's why an **inverted index** (word → which chunks contain it) makes it fast:
  you only ever touch the handful of words in the query.

The next note swaps this sparse vector for a **dense** one (a few hundred numbers,
all meaningful) → [Vectors & Embeddings](03-vectors-and-embeddings.md).

## When to use it — and the one big limit

- ✅ **Fast, cheap, no model, no training.** A genuinely strong baseline, and hard
  to beat on exact-terminology text (names, error codes, product IDs, jargon).
  Fully **explainable** — you can see exactly which words scored.
- ❌ **Only matches exact words** (after stemming). "car" will **not** match
  "automobile"; a reworded query misses relevant docs. That blind spot is precisely
  what [Semantic Search](04-semantic-search.md) fixes — and [Hybrid Search](06-hybrid-search.md)
  keeps *both* strengths.

## Key takeaways (30-second refresh)

- **TF** = how often *here*; **IDF** = how rare *overall*; score = `Σ tf·idf` over shared words.
- **BM25** = TF-IDF + **saturation (`k1`)** + **length penalty (`b`)`.
- It's a sparse-vector dot product, made fast by an inverted index.
- Excellent baseline — but blind to meaning/synonyms.

---

**In this project:** implemented in [`bm25.ex`](../lib/learning_rag/search/bm25.ex)
and [`tf_idf.ex`](../lib/learning_rag/search/tf_idf.ex) (the formula lives in
readable SQL). Try it live: `mix rag.search "..." --scorer bm25 --k1 1.2 --b 0.75`,
or the search page. On the SciFact benchmark, BM25 scores NDCG@10 ≈ 0.69 vs plain
TF-IDF's 0.54 — those two knobs are worth ~15 points.
