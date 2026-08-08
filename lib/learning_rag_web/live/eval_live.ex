defmodule LearningRagWeb.EvalLive do
  @moduledoc """
  Runs a scorer over the 300 SciFact test queries and shows the mean IR metrics.
  Each run is appended to a table, so you can tweak parameters and compare runs
  side by side — the "tune and visualize" loop.

  Evaluation uses the stored query embeddings, so even semantic/hybrid runs need
  no OpenAI key. A run takes a few seconds (longer for semantic/hybrid), so it's
  executed asynchronously and the page stays responsive.
  """
  use LearningRagWeb, :live_view

  alias LearningRag.Search.{Bm25, TfIdf, Semantic, Hybrid}
  alias LearningRag.Eval.Runner

  @scorers %{"bm25" => Bm25, "tfidf" => TfIdf, "semantic" => Semantic, "hybrid" => Hybrid}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign_params(default_params())
     |> assign(runs: [], running: false, next_id: 0)}
  end

  @impl true
  def handle_event("validate", %{"eval" => params}, socket) do
    {:noreply, assign_params(socket, Map.merge(socket.assigns.params, params))}
  end

  def handle_event("run", %{"eval" => params}, socket) do
    params = Map.merge(socket.assigns.params, params)
    scorer = Map.fetch!(@scorers, params["scorer"])
    opts = build_opts(params)
    label = describe(params["scorer"], opts)

    socket =
      socket
      |> assign_params(params)
      |> assign(:running, true)
      |> start_async(:eval, fn ->
        %{mean: mean, query_count: count} = Runner.run(scorer, opts)
        %{label: label, metrics: mean, count: count}
      end)

    {:noreply, socket}
  end

  def handle_event("clear", _params, socket) do
    {:noreply, assign(socket, runs: [])}
  end

  @impl true
  def handle_async(:eval, {:ok, run}, socket) do
    run = Map.put(run, :id, socket.assigns.next_id)

    {:noreply,
     assign(socket,
       running: false,
       next_id: socket.assigns.next_id + 1,
       runs: [run | socket.assigns.runs]
     )}
  end

  def handle_async(:eval, {:exit, reason}, socket) do
    {:noreply,
     socket |> assign(:running, false) |> put_flash(:error, "Eval failed: #{inspect(reason)}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Evaluate
        <:subtitle>
          Score a scorer over the 300 SciFact queries; runs stack up for comparison.
        </:subtitle>
      </.header>

      <.form for={@form} id="eval-form" phx-change="validate" phx-submit="run" class="space-y-4">
        <div class="rounded-lg border border-base-300 bg-base-200/40 p-4">
          <p class="mb-3 text-xs font-semibold uppercase tracking-wide opacity-60">Parameters</p>

          <div class="flex flex-wrap items-end gap-x-4 gap-y-3">
            <.input
              field={@form[:scorer]}
              type="select"
              label="Scorer"
              class="select w-32"
              options={~w(bm25 tfidf semantic hybrid)}
              hint="Which retrieval method to evaluate. bm25 and tfidf match on shared keywords; semantic matches on meaning via embeddings; hybrid fuses the two. Semantic/hybrid use the stored query embeddings, so no API key is needed."
            />

            <.input
              :if={@params["scorer"] in ["bm25", "hybrid"]}
              field={@form[:k1]}
              type="number"
              label="k1"
              step="0.1"
              min="0"
              class="input w-20"
              hint="BM25 term-frequency saturation. How fast repeated words stop adding score: a higher k1 lets repeats keep counting longer, while k1 = 0 ignores counts entirely (only whether a word appears)."
            />
            <.input
              :if={@params["scorer"] in ["bm25", "hybrid"]}
              field={@form[:b]}
              type="number"
              label="b"
              step="0.05"
              min="0"
              max="1"
              class="input w-20"
              hint="BM25 length normalization. How much long chunks are penalized so they don't rank high just for having more words: b = 0 ignores length, b = 1 applies the full penalty."
            />

            <.input
              :if={@params["scorer"] == "hybrid"}
              field={@form[:method]}
              type="select"
              label="method"
              class="select w-32"
              options={~w(rrf weighted)}
              hint="How the BM25 and semantic rankings are combined. rrf merges by rank only (no score scaling needed); weighted rescales each score list to 0–1 and blends them."
            />
            <.input
              :if={@params["scorer"] == "hybrid" and @params["method"] == "rrf"}
              field={@form[:k]}
              type="number"
              label="k (RRF)"
              step="1"
              min="1"
              class="input w-24"
              hint="RRF constant. Larger values flatten the weighting so the very top ranks count relatively less. The usual default is 60."
            />
            <.input
              :if={@params["scorer"] == "hybrid" and @params["method"] == "weighted"}
              field={@form[:beta]}
              type="number"
              label="beta"
              step="0.1"
              min="0"
              max="1"
              class="input w-20"
              hint="Weighted-fusion blend. 0 = pure BM25, 1 = pure semantic, 0.5 = equal weight on each."
            />

            <div class="mb-2">
              <.button variant="primary" disabled={@running} phx-disable-with="Running…">
                {if @running, do: "Running…", else: "Run evaluation"}
              </.button>
            </div>
          </div>
        </div>
      </.form>

      <p :if={@running} class="text-sm opacity-70" id="running">
        <.icon name="hero-arrow-path" class="size-4 motion-safe:animate-spin" />
        evaluating 300 queries…
      </p>

      <div :if={@runs == [] and not @running} class="text-sm opacity-70" id="empty">
        No runs yet. Pick a scorer and hit “Run evaluation”. (Needs <code>mix rag.index</code>; semantic/hybrid also need <code>mix rag.embed</code>.)
      </div>

      <div :if={@runs != []} class="space-y-2">
        <div class="flex items-center justify-between">
          <p class="text-sm opacity-70">{length(@runs)} runs</p>
          <.button phx-click="clear">Clear</.button>
        </div>

        <table class="w-full text-sm">
          <thead class="text-left align-bottom opacity-70">
            <tr>
              <th class="py-2 pr-3">Run</th>
              <th class="py-2 px-2">
                <span class="flex items-center justify-end gap-1">
                  NDCG@10
                  <.hint text="Normalized Discounted Cumulative Gain at 10. Ranking quality that rewards putting relevant docs near the top, with a smooth position discount. The headline IR metric." />
                </span>
              </th>
              <th class="py-2 px-2">
                <span class="flex items-center justify-end gap-1">
                  MRR@10
                  <.hint text="Mean Reciprocal Rank at 10. 1 divided by the rank of the first relevant result, averaged over queries — higher means relevant hits appear sooner." />
                </span>
              </th>
              <th class="py-2 px-2">
                <span class="flex items-center justify-end gap-1">
                  R@10
                  <.hint text="Recall at 10. Of all the documents judged relevant for a query, the fraction that appear in the top 10." />
                </span>
              </th>
              <th class="py-2 px-2">
                <span class="flex items-center justify-end gap-1">
                  MAP
                  <.hint text="Mean Average Precision. Averages precision at each relevant hit, rewarding rankings that place relevant docs early." />
                </span>
              </th>
              <th class="py-2 px-2">
                <span class="flex items-center justify-end gap-1">
                  P@5
                  <.hint text="Precision at 5. The fraction of the top 5 results that are relevant. It looks low here because SciFact averages only ~1 relevant doc per query." />
                </span>
              </th>
              <th class="py-2 pl-2 text-right">queries</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={run <- @runs} class="border-t border-base-300" id={"run-#{run.id}"}>
              <td class="py-1.5 pr-3 font-medium">{run.label}</td>
              <td class="py-1.5 px-2 text-right font-mono">{metric(run.metrics, :ndcg_at_10)}</td>
              <td class="py-1.5 px-2 text-right font-mono">{metric(run.metrics, :mrr_at_10)}</td>
              <td class="py-1.5 px-2 text-right font-mono">{metric(run.metrics, :r_at_10)}</td>
              <td class="py-1.5 px-2 text-right font-mono">{metric(run.metrics, :map)}</td>
              <td class="py-1.5 px-2 text-right font-mono">{metric(run.metrics, :p_at_5)}</td>
              <td class="py-1.5 pl-2 text-right opacity-60">{run.count}</td>
            </tr>
          </tbody>
        </table>
      </div>

      <p class="pt-2 text-xs opacity-50">
        Evaluated on
        <.link
          href="https://github.com/beir-cellar/beir"
          target="_blank"
          rel="noopener"
          class="underline"
        >
          SciFact (BEIR)
        </.link>
        — 300 queries with human relevance judgments. Published BM25 baseline NDCG@10 ≈ 0.665.
      </p>
    </Layouts.app>
    """
  end

  # --- opts / labels --------------------------------------------------------

  defp build_opts(params) do
    case params["scorer"] do
      "bm25" ->
        [k1: to_float(params["k1"], 1.2), b: to_float(params["b"], 0.75)]

      "hybrid" ->
        [
          method: params["method"] || "rrf",
          k: to_int(params["k"], 60),
          beta: to_float(params["beta"], 0.5),
          k1: to_float(params["k1"], 1.2),
          b: to_float(params["b"], 0.75)
        ]

      _ ->
        []
    end
  end

  defp describe("bm25", opts), do: "bm25 (k1=#{opts[:k1]}, b=#{opts[:b]})"
  defp describe("tfidf", _opts), do: "tfidf"
  defp describe("semantic", _opts), do: "semantic"

  defp describe("hybrid", opts) do
    case opts[:method] do
      "weighted" -> "hybrid weighted (β=#{opts[:beta]})"
      _ -> "hybrid rrf (k=#{opts[:k]})"
    end
  end

  defp metric(metrics, key) do
    case Map.get(metrics, key) do
      nil -> "—"
      value -> :erlang.float_to_binary(value, decimals: 4)
    end
  end

  # --- params/form ----------------------------------------------------------

  defp assign_params(socket, params) do
    socket |> assign(:params, params) |> assign(:form, to_form(params, as: :eval))
  end

  defp default_params do
    %{
      "scorer" => "bm25",
      "k1" => "1.2",
      "b" => "0.75",
      "method" => "rrf",
      "k" => "60",
      "beta" => "0.5"
    }
  end

  defp to_float(value, default) do
    case Float.parse(to_string(value)) do
      {float, _} -> float
      :error -> default
    end
  end

  defp to_int(value, default) do
    case Integer.parse(to_string(value)) do
      {int, _} -> int
      :error -> default
    end
  end
end
