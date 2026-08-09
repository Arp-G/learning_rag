# RAG vs Fine-Tuning — which tool for which problem

> **TL;DR** — **RAG adds knowledge; fine-tuning changes behavior.** If the model is
> missing *facts* (private, fresh, or too many to fit in a prompt), retrieve them
> and paste them in → RAG. If the model has the facts but won't *act* the way you
> need (tone, format, a repetitive task), train new behavior into its weights →
> fine-tuning. Reach for RAG first: it's cheaper, updatable, and explainable.

## The intuition: a new hire

Picture onboarding a smart new employee who doesn't know your company yet.

- **RAG** = hand them the relevant handbook page *every time* they answer. Their
  brain is unchanged; they just have the right document open. Swap the page and the
  answer changes instantly.
- **Fine-tuning** = send them on months of training until they *naturally* answer
  in your house style — no handbook needed, but retraining them again is slow and
  costly.

The split that falls out of this: RAG is about **what the model can see right now**;
fine-tuning is about **what the model has become**.

## The one test: knowledge or behavior?

| The problem is… | You need | Why |
|---|---|---|
| "It doesn't *know* our Q3 policy / this codebase / today's prices" | **RAG** | missing facts → supply them at answer time |
| "It knows, but won't answer as strict JSON / in our tone / our format" | **Fine-tuning** | the *skill or style* lives in the weights |

Rule of thumb: **if pasting the right text into the prompt would fix it, it's a
knowledge gap → RAG.** If pasting text in *doesn't* help because the model just
won't behave, it's a behavior gap → fine-tuning.

## RAG in one line

Retrieve relevant chunks, inject them into the prompt, then generate. **The weights
never change** — you're editing the *input*, not the model.

- ✅ Always current (re-index and you're done), easy to update, and **explainable** —
  you can cite which chunk produced the answer.
- ✅ Handles huge or private collections no prompt could ever hold.
- ❌ Only as good as retrieval — miss the right chunk and the answer is wrong. (This
  is why most of these notes are about retrieval *quality*.)
- ❌ Adds a retrieval step (latency) and a knowledge base to maintain.

## Fine-tuning in one line

Show the model thousands of `(input → ideal output)` examples and nudge its weights
until it reproduces that behavior. **Teaches a skill or style, not fresh facts.**

- ✅ Bakes inconsistent behavior; shorter prompts; faster (no retrieval step).
- ✅ Can make a small, cheap model do one narrow task surprisingly well.
- ❌ Expensive to train, slow to update, and goes stale (baked-in facts age badly).
- ❌ Can get *worse* at everything outside the target task — it specialized.

> **Common trap:** trying to fine-tune *facts* into a model. It's an expensive,
> lossy way to store knowledge that's out of date the moment the facts change — and
> the model will confidently invent the gaps. Facts belong in retrieval, not weights.

## They combine

Production systems often do both: a **fine-tuned model** (knows the house style and
output format) answering over **retrieved context** (supplies the current facts).
Retrieval keeps it correct; fine-tuning keeps it on-brand.

## The order to try things

Cheapest and most reversible first:

1. **Better prompting** — clearer instructions, a few examples, an explicit output
   format. Fixes a surprising amount for almost no cost.
2. **RAG** — when the gap is missing or changing *knowledge*.
3. **Agentic / orchestration** — let the model plan and retrieve in steps
   ([Agentic RAG](14-agentic-rag.md)).
4. **Fine-tuning** — last, when *behavior* still isn't consistent enough.

Fine-tuning is usually the *last* optimization, not the first — most effort, hardest
to undo.

## Key takeaways

- **RAG = knowledge, fine-tuning = behavior.** They solve different problems.
- The test: *would pasting text into the prompt fix it?* Yes → RAG. No → fine-tuning.
- RAG is current / updatable / explainable; fine-tuning is consistent / compact /
  fast at inference.
- Don't fine-tune facts. Order: prompt → RAG → agentic → fine-tune.

---

**In this project:** `learning_rag` is entirely the **RAG** side — we build and
measure the *retriever* (sparse → dense → hybrid) and never touch model weights.
Every other note is about making the retrieve-then-prompt path better. The
[evaluation metrics](11-retrieval-evaluation-metrics.md) exist to measure retrieval
quality directly — RAG's make-or-break step.
