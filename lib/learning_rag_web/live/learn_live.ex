defmodule LearningRagWeb.LearnLive do
  @moduledoc """
  In-app viewer for the study notes that live in `notes/*.md`.

  It reads the markdown at request time, renders it to HTML with Earmark, and
  rewrites the links so the notes are browsable *inside* the app:

    * `04-semantic-search.md`  -> `/learn/04-semantic-search`  (sibling note)
    * `glossary.md` / `README.md` -> `/learn/glossary` / `/learn`
    * `../lib/....ex`          -> the file on GitHub (opens in a new tab)

  Same files served on GitHub — this just puts them next to the live search and
  eval tools so theory and implementation sit side by side.
  """
  use LearningRagWeb, :live_view

  # Project-root notes/ dir, resolved relative to this source file. Read fresh on
  # every request, so editing a note shows up on refresh (no recompile needed).
  @notes_dir Path.expand("../../../notes", __DIR__)
  @repo_blob "https://github.com/Arp-G/learning_rag/blob/master"

  # The learning path — grouped by section. Drives the sidebar, prev/next links,
  # and slug validation. Order matches notes/README.md.
  @sections [
    {"Foundations & retrieval",
     [
       {"01-rag-vs-fine-tuning", "RAG vs Fine-Tuning"},
       {"02-tf-idf-and-bm25", "TF-IDF & BM25"},
       {"03-vectors-and-embeddings", "Vectors & Embeddings"},
       {"04-semantic-search", "Semantic Search"},
       {"05-searching-algorithms", "Searching Algorithms"},
       {"06-hybrid-search", "Hybrid Search"},
       {"07-re-ranking", "Re-Ranking"}
     ]},
    {"The input side",
     [
       {"08-chunking", "Chunking"},
       {"09-advanced-chunking", "Advanced Chunking"},
       {"10-query-rewriting", "Query Rewriting"}
     ]},
    {"Measuring it", [{"11-retrieval-evaluation-metrics", "Retrieval Metrics"}]},
    {"Generation",
     [
       {"12-prompt-engineering", "Prompt Engineering"},
       {"13-evaluating-llm-performance", "Evaluating LLM Performance"}
     ]},
    {"Systems & advanced",
     [
       {"14-agentic-rag", "Agentic RAG"},
       {"15-production-rag", "Production RAG"}
     ]},
    {"LLM background",
     [
       {"16-sampling-strategies", "Sampling Strategies"},
       {"17-llm-characteristics", "LLM Characteristics"}
     ]}
  ]

  # Flat, ordered list of the notes (for prev/next) and the set of valid slugs.
  @ordered Enum.flat_map(@sections, fn {_section, notes} -> notes end)
  @valid_slugs ["README", "glossary" | Enum.map(@ordered, fn {slug, _title} -> slug end)]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, sections: @sections)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    slug = params["slug"] || "README"

    if slug in @valid_slugs do
      {:noreply, load_note(socket, slug)}
    else
      {:noreply,
       socket
       |> put_flash(:error, "No note called “#{slug}”.")
       |> push_navigate(to: ~p"/learn")}
    end
  end

  defp load_note(socket, slug) do
    {title, prev, next} = nav_info(slug)

    html =
      @notes_dir
      |> Path.join("#{slug}.md")
      |> File.read!()
      |> render_markdown()

    socket
    |> assign(slug: slug, html: html, prev: prev, next: next)
    |> assign(:page_title, "Learn · #{title}")
  end

  # --- markdown -> in-app HTML -------------------------------------------------

  defp render_markdown(markdown) do
    markdown
    |> to_html()
    |> add_heading_ids()
    |> rewrite_links()
  end

  defp to_html(markdown) do
    # smartypants off so code-ish text (e.g. "--scorer") is left exactly as written.
    case Earmark.as_html(markdown, %Earmark.Options{smartypants: false}) do
      {:ok, html, _messages} -> html
      {:error, html, _messages} -> html
    end
  end

  # Give headings GitHub-style id slugs so in-app "glossary.md#section" anchors
  # resolve (Earmark emits no ids; GitHub does — this keeps the two in parity).
  defp add_heading_ids(html) do
    Regex.replace(~r{<h([1-6])>(.*?)</h\1>}s, html, fn _full, level, inner ->
      case slugify(strip_tags(inner)) do
        "" -> "<h#{level}>#{inner}</h#{level}>"
        slug -> ~s(<h#{level} id="#{slug}">#{inner}</h#{level}>)
      end
    end)
  end

  defp strip_tags(html), do: String.replace(html, ~r/<[^>]+>/, "")

  defp slugify(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.trim()
    |> String.replace(~r/\s+/, "-")
  end

  # Rewrite every href so the notes' relative links work inside the app.
  defp rewrite_links(html) do
    Regex.replace(~r/href="([^"]*)"/, html, fn _match, url -> rewrite_href(url) end)
  end

  defp rewrite_href(url) do
    cond do
      String.starts_with?(url, "http") ->
        external(url)

      # code/repo links like ../lib/... or ../test/... -> GitHub
      String.starts_with?(url, "../") ->
        external("#{@repo_blob}/#{String.replace_prefix(url, "../", "")}")

      # sibling note links like 04-semantic-search.md(#anchor)
      String.contains?(url, ".md") ->
        {file, anchor} = split_anchor(url)
        ~s(href="#{note_path(file)}#{anchor}")

      true ->
        ~s(href="#{url}")
    end
  end

  defp external(url), do: ~s(href="#{url}" target="_blank" rel="noopener")

  defp note_path("README.md"), do: ~p"/learn"
  defp note_path("glossary.md"), do: ~p"/learn/glossary"
  defp note_path(file), do: ~p"/learn/#{String.replace_suffix(file, ".md", "")}"

  defp split_anchor(url) do
    case String.split(url, "#", parts: 2) do
      [file] -> {file, ""}
      [file, anchor] -> {file, "#" <> anchor}
    end
  end

  # --- navigation --------------------------------------------------------------

  defp nav_info("README"), do: {"Study notes", nil, List.first(@ordered)}
  defp nav_info("glossary"), do: {"Glossary", nil, nil}

  defp nav_info(slug) do
    index = Enum.find_index(@ordered, fn {s, _title} -> s == slug end)
    {_slug, title} = Enum.at(@ordered, index)
    prev = if index > 0, do: Enum.at(@ordered, index - 1)
    next = Enum.at(@ordered, index + 1)
    {title, prev, next}
  end

  # --- view --------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} max_width="max-w-6xl">
      <div class="grid grid-cols-1 lg:grid-cols-[15rem_minmax(0,1fr)] gap-8">
        <aside class="hidden lg:block">
          <nav class="sticky top-8 text-sm space-y-3">
            <.link
              navigate={~p"/learn"}
              class={["block font-semibold", @slug == "README" && "text-primary"]}
            >
              📓 Study notes
            </.link>

            <div :for={{section, notes} <- @sections} class="space-y-1">
              <div class="text-xs uppercase tracking-wide opacity-50 pt-2">{section}</div>
              <.link
                :for={{slug, title} <- notes}
                navigate={~p"/learn/#{slug}"}
                class={[
                  "block leading-snug hover:text-primary",
                  @slug == slug && "text-primary font-medium"
                ]}
              >
                {title}
              </.link>
            </div>

            <.link
              navigate={~p"/learn/glossary"}
              class={[
                "block pt-2 hover:text-primary",
                @slug == "glossary" && "text-primary font-medium"
              ]}
            >
              📖 Glossary
            </.link>
          </nav>
        </aside>

        <article class="min-w-0">
          <.link :if={@slug != "README"} navigate={~p"/learn"} class="lg:hidden text-sm text-primary">
            ← All notes
          </.link>

          <div class="note-body">{raw(@html)}</div>

          <nav
            :if={@prev || @next}
            class="mt-12 pt-6 border-t border-base-300 flex items-center justify-between gap-4"
          >
            <.link :if={@prev} navigate={~p"/learn/#{elem(@prev, 0)}"} class="btn btn-ghost btn-sm">
              ← {elem(@prev, 1)}
            </.link>
            <span :if={!@prev}></span>
            <.link
              :if={@next}
              navigate={~p"/learn/#{elem(@next, 0)}"}
              class="btn btn-ghost btn-sm ml-auto"
            >
              {elem(@next, 1)} →
            </.link>
          </nav>
        </article>
      </div>
    </Layouts.app>
    """
  end
end
