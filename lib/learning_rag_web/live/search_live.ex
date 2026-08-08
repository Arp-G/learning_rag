defmodule LearningRagWeb.SearchLive do
  @moduledoc """
  Interactive search: type a query, pick a scorer, tweak its parameters, and see
  the ranked chunks with their score breakdown. This is the whole retrieval stack
  (Phases 1–3) made pokeable — change k1/b/k/beta and watch the ranking move.

  Sparse scorers (bm25/tfidf) run offline. Semantic/hybrid embed the query live
  via OpenAI, so they need OPENAI_API_KEY set on the server (errors are surfaced,
  not crashed).
  """
  use LearningRagWeb, :live_view

  alias LearningRag.Search.{Bm25, TfIdf, Semantic, Hybrid}

  @scorers %{"bm25" => Bm25, "tfidf" => TfIdf, "semantic" => Semantic, "hybrid" => Hybrid}

  # A few SciFact-style claims to try with one click.
  @samples [
    "vitamin D deficiency increases risk of bone fractures",
    "aspirin reduces the risk of colorectal cancer",
    "breastfeeding lowers infant infection rates",
    "statins increase the risk of type 2 diabetes"
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign_params(default_params())
     |> assign(results: nil, error: nil, expanded: MapSet.new(), samples: @samples)}
  end

  @impl true
  def handle_event("validate", %{"search" => params}, socket) do
    {:noreply, assign_params(socket, Map.merge(socket.assigns.params, params))}
  end

  def handle_event("search", %{"search" => params}, socket) do
    do_search(socket, Map.merge(socket.assigns.params, params))
  end

  def handle_event("use_sample", %{"q" => query}, socket) do
    do_search(socket, Map.put(socket.assigns.params, "query", query))
  end

  def handle_event("toggle_full", %{"id" => id}, socket) do
    id = String.to_integer(id)
    expanded = socket.assigns.expanded

    expanded =
      if MapSet.member?(expanded, id),
        do: MapSet.delete(expanded, id),
        else: MapSet.put(expanded, id)

    {:noreply, assign(socket, :expanded, expanded)}
  end

  defp do_search(socket, params) do
    socket = assign_params(socket, params)

    case run_search(params) do
      {:ok, results} ->
        {:noreply, assign(socket, results: results, error: nil, expanded: MapSet.new())}

      {:error, message} ->
        {:noreply, assign(socket, results: nil, error: message)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Search
        <:subtitle>Query the corpus with any scorer and tune its parameters live.</:subtitle>
      </.header>

      <.form for={@form} id="search-form" phx-change="validate" phx-submit="search" class="space-y-4">
        <.input
          field={@form[:query]}
          type="text"
          label="Query"
          autocomplete="off"
          phx-debounce="300"
          placeholder="e.g. vitamin D deficiency and bone fractures"
        />

        <div class="rounded-lg border border-base-300 bg-base-200/40 p-4">
          <p class="mb-3 text-xs font-semibold uppercase tracking-wide opacity-60">Parameters</p>

          <div class="flex flex-wrap items-end gap-x-4 gap-y-3">
            <.input
              field={@form[:scorer]}
              type="select"
              label="Scorer"
              class="select w-32"
              options={~w(bm25 tfidf semantic hybrid)}
              hint="How results are ranked. bm25 and tfidf match on shared keywords; semantic matches on meaning via embeddings, so it can find paraphrases with no shared words; hybrid fuses the two."
            />
            <.input
              field={@form[:top_k]}
              type="number"
              label="top_k"
              min="1"
              class="input w-20"
              hint="How many results to show. This only changes the display — the underlying ranking is unchanged."
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
              <.button variant="primary" phx-disable-with="Searching…">Search</.button>
            </div>
          </div>
        </div>
      </.form>

      <div class="flex flex-wrap items-center gap-2">
        <span class="text-sm opacity-60">Try:</span>
        <button
          :for={sample <- @samples}
          type="button"
          phx-click="use_sample"
          phx-value-q={sample}
          class="rounded-full border border-base-300 px-3 py-1.5 text-xs hover:bg-base-200"
        >
          {sample}
        </button>
      </div>

      <div :if={@error} class="rounded-md bg-error/10 px-4 py-3 text-sm text-error" id="search-error">
        {@error}
      </div>

      <div :if={@results} class="space-y-3">
        <p class="text-sm opacity-70">{length(@results)} results</p>

        <p :if={@results == []} class="text-sm opacity-70" id="no-results">
          No matches. (Semantic/hybrid need <code>mix rag.embed</code> to have run.)
        </p>

        <div
          :for={{result, rank} <- Enum.with_index(@results, 1)}
          class="rounded-lg border border-base-300 p-4"
          id={"result-#{result.chunk_id}"}
        >
          <div class="flex items-baseline justify-between gap-3">
            <span class="font-semibold">{rank}. {result.title}</span>
            <span class="shrink-0 font-mono text-sm opacity-70">{fmt(result.score)}</span>
          </div>
          <p class="mt-1 text-xs opacity-60">
            doc {result.doc_external_id} · chunk {result.chunk_index}
          </p>

          <p class="mt-2 text-sm opacity-80">
            {if MapSet.member?(@expanded, result.chunk_id),
              do: result.text,
              else: snippet(result.text)}
          </p>
          <button
            :if={String.length(result.text) > 240}
            type="button"
            phx-click="toggle_full"
            phx-value-id={result.chunk_id}
            class="mt-1 text-xs text-primary hover:underline"
          >
            {if MapSet.member?(@expanded, result.chunk_id), do: "show less", else: "show full chunk"}
          </button>

          <div :if={result.breakdown != []} class="mt-3 flex flex-wrap items-center gap-2">
            <span class="text-xs opacity-50">{breakdown_heading(result.breakdown)}</span>
            <span
              :for={entry <- result.breakdown}
              class="rounded border border-base-300 bg-base-100 px-2 py-0.5 font-mono text-xs"
            >
              {breakdown_label(entry)}
            </span>
          </div>
        </div>
      </div>

      <p class="pt-2 text-xs opacity-50">
        Corpus:
        <.link
          href="https://github.com/beir-cellar/beir"
          target="_blank"
          rel="noopener"
          class="underline"
        >
          SciFact (BEIR)
        </.link>
        — ~5.2K scientific abstracts with 300 labeled test queries.
      </p>
    </Layouts.app>
    """
  end

  # --- search ---------------------------------------------------------------

  defp run_search(params) do
    case String.trim(params["query"] || "") do
      "" ->
        {:ok, []}

      query ->
        scorer = Map.fetch!(@scorers, params["scorer"])

        try do
          {:ok, scorer.search(query, build_opts(params))}
        rescue
          error -> {:error, Exception.message(error)}
        end
    end
  end

  # Translate the string form params into the keyword opts each scorer expects.
  defp build_opts(params) do
    base = [top_k: to_int(params["top_k"], 10)]

    case params["scorer"] do
      "bm25" ->
        base ++ [k1: to_float(params["k1"], 1.2), b: to_float(params["b"], 0.75)]

      "hybrid" ->
        base ++
          [
            method: params["method"] || "rrf",
            k: to_int(params["k"], 60),
            beta: to_float(params["beta"], 0.5),
            k1: to_float(params["k1"], 1.2),
            b: to_float(params["b"], 0.75)
          ]

      _ ->
        base
    end
  end

  # --- rendering helpers ----------------------------------------------------

  # BM25/TF-IDF breakdowns are per-term (the query's sparse-vector contributions
  # for this chunk); hybrid's are per-source. A little label says which.
  defp breakdown_heading([%{"source" => _} | _]), do: "sources:"
  defp breakdown_heading(_term_based), do: "vector:"

  defp breakdown_label(%{"source" => source} = entry), do: "#{source} ##{entry["rank"]}"
  defp breakdown_label(%{"term" => term} = entry), do: "#{term}: #{fmt(entry["contribution"])}"

  defp snippet(text) do
    if String.length(text) > 240, do: String.slice(text, 0, 240) <> "…", else: text
  end

  defp fmt(number) when is_float(number), do: :erlang.float_to_binary(number, decimals: 4)
  defp fmt(number), do: to_string(number)

  # --- params/form ----------------------------------------------------------

  defp assign_params(socket, params) do
    socket |> assign(:params, params) |> assign(:form, to_form(params, as: :search))
  end

  defp default_params do
    %{
      "query" => "",
      "scorer" => "bm25",
      "top_k" => "10",
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
