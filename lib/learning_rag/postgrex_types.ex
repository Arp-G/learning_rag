# This file defines the module LearningRag.PostgrexTypes — but not with the
# usual `defmodule`. The macro below GENERATES that module: it teaches Postgres
# (via Postgrex) how to encode/decode pgvector's `vector` wire type, so a
# vector column comes back as a %Pgvector{} struct and we can send one as a
# query parameter.
#
# It lives in lib/ as plain top-level code (not inside a function) so it runs
# at compile time — the module must already exist when the Repo boots and reads
# its `types:` key (set in config/config.exs). That's also why `mix deps.get`
# for pgvector has to happen before this file compiles.
#
# `Pgvector.extensions()` supplies the vector codec. We append
# `Ecto.Adapters.Postgres.extensions()` (currently an empty list) purely to
# follow pgvector's documented pattern and stay future-proof..
Postgrex.Types.define(
  LearningRag.PostgrexTypes,
  Pgvector.extensions() ++ Ecto.Adapters.Postgres.extensions()
)
