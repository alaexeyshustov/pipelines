# ADR 0014: Embedding model for vector search and semantic dedup

## Status
Accepted (GH #225, part of #215; unblocks #226 and #227)

## Context

Emails (subject and body, possibly long HTML-derived text) and Documents (OCR markdown, possibly long) need vectors for KNN search (#226) and near-duplicate detection (#227). The legacy `email_vectors` table (`FLOAT[1536]`, OpenAI default) was dropped. The issue leans open source and asks for model, dimension, hosted vs local, sync vs background, and a re-embedding strategy.

Facts from the repo:

- RubyLLM 2.1.1 has `RubyLLM.embed(text_or_array, model:, provider:, dimensions:, task_type:, ...)`; arrays are embedded in one call. Embeddings are implemented for OpenAI, Mistral (`output_dimension`), Gemini, Vertex AI, Azure, OpenRouter, Perplexity, Cohere, GPUStack, and the shared ChatCompletions protocol (so Ollama and any OpenAI-compatible server such as vLLM or Hetzner Inference via `openai_api_base`); `default_embedding_model` is `text-embedding-3-small`. Whether `dimensions:` is honoured by Ollama's `/v1/embeddings` was not verified.
- `config/initializers/ruby_llm.rb` configures OpenAI, Mistral, Gemini and Anthropic keys (Mistral is already used for chat and OCR). No Ollama base URL is configured yet (#208 covers local models).
- sqlite-vec 0.1.9 is loaded on every connection. `vec0` is brute-force only (no ANN). It supports `float[N]`, `int8[N]` and `bit[N]`, and `distance_metric=cosine` (the binary contains `vec_distance_cosine`/`hamming`; declaring it on a column was not exercised here). Author benchmarks (v0.1.0, M1 mini): 100k vectors at 1024 dims, under 75 ms per KNN; 1M at 3072 dims, 8.5 s. Personal scale (thousands to tens of thousands of rows) is a few ms to tens of ms.
- Deployment: Hetzner is planned (#213); the dev machine has about 4 GB RAM, which rules out models over roughly 1B parameters locally.
- Languages (confirmed by the user): mail and documents are in English, German and Russian. Multilingual quality, including Russian, is a requirement.

## Options

Scores are MTEB Multilingual v2 Mean(Task) from the model cards, so they are comparable only within that table. Prices are per 1M input tokens.

| Model | Hosted / local | Dims | Context | Multilingual | Cost / RAM | License | RubyLLM |
|---|---|---|---|---|---|---|---|
| **Qwen3-Embedding-0.6B** | Local (Ollama `qwen3-embedding:0.6b`); hosted only for 4B/8B (OpenRouter $0.02 / $0.01) | up to 1024, MRL 32-1024 | 32k | 64.33 (100+ languages) | ~0.6 GB at Q8 (estimate, unverified); free locally | Apache-2.0 | Ollama via ChatCompletions protocol |
| EmbeddingGemma-300m (`embeddinggemma`) | Local (Ollama, 2.7M pulls) | 768, MRL 512/256/128 | 2048 | 61.15 (768d); 60.71 (512d) | ~0.3 GB (Ollama tag sizes for the 270m successor: 304-378 MB); free | Gemma terms (gated on HF) | Ollama |
| multilingual-e5-large-instruct | Local (via other runtimes; Ollama has `paraphrase-multilingual`, not this) | 1024 | 512 | 63.22 | ~0.56B params | MIT | OpenAI-compatible server |
| bge-m3 | Local (Ollama `bge-m3`, 567M); hosted OpenRouter $0.01 | 1024 | 8192 | 59.56 | ~1.2 GB fp16 (estimate) | MIT | Ollama, OpenRouter; RubyLLM also reads its sparse vectors |
| nomic-embed-text-v2-moe | Local (Ollama) | 768, MRL to 256 | 512 | MIRACL 65.80 (different metric) | 475M total / 305M active | Apache-2.0 | Ollama |
| mistral-embed | Hosted (Mistral) | 1024 (fixed per docs; `output_dimension` not documented for it) | 8000 | Not verified (no first-party MTEB figure found) | $0.10 (RubyLLM registry; not on Mistral's pricing page) | Proprietary | Native, key already present |
| text-embedding-3-small | Hosted (OpenAI) | 1536, `dimensions:` supported | 8191 | Not verified (weaker than the Gemini and Qwen3 rows; no table in sources read) | $0.02 | Proprietary | Native, key already present |
| gemini-embedding-001 / -2 | Hosted (Google) | 3072, MRL 128-3072 (768 recommended) | 2048 / 8192 | 68.37 (Gemini Embedding, MTEB multi.) | 001: $0.15, 2: $0.20, free tier on standard; batch half price | Proprietary | Native, key already present |
| granite-embedding-278m-multilingual | Local (Ollama) | not read | not read | Russian not in its language list (German is) | 278M | Apache-2.0 | Ollama |

Notes: `codestral-embed` is the only other Mistral embedding model found and is code-oriented; no newer general Mistral embedding model was found. Gemini 2 states its vector space is incompatible with 001. Qwen3 needs a one-line task instruction on queries (documents none), which RubyLLM does not add, so the app must prefix queries itself (`Instruct: ...\nQuery: ...`). Dedup (#227) compares document to document and needs no prefix.

## Decision

**Chosen: Qwen3-Embedding-0.6B, local via Ollama, 1024 dims (float32).** Best multilingual score among models that fit a 4 GB machine (64.33 vs 61.15 EmbeddingGemma, 59.56 bge-m3), Apache-2.0, 32k context (no chunking pressure), MRL lets us truncate to 768 or 512 later without re-calling the model. Cost is zero per call; RAM is small. Costs: it needs Ollama (a new service on dev and on Hetzner; CPU-only embedding speed untested here) and the query-side instruction prefix. Open weights mean it can be moved to any hosted OpenAI-compatible endpoint (a larger Qwen3 is on OpenRouter) without the vector space changing only if the same model size is used; 4B/8B are different spaces.

**Runner-up: mistral-embed (hosted).** Zero new infrastructure, key already configured, 1024 dims, 8000 tokens, about $0.10 per 1M tokens (a 10k-email corpus at ~500 tokens is about 5M tokens, so roughly $0.50 per full re-embed). Downsides: proprietary, multilingual quality unverified, email content leaves the machine, not open source.

Close third: EmbeddingGemma-300m if RAM or CPU latency of the 0.6B proves a problem (768 dims; Gemma license).

## Other decisions

**Sync vs background.** Background job. `Email::EmbedJob` / `Document::EmbedJob`, enqueued from the existing chains (`Email::ProcessJob` after storing; document creation and OCR completion). Models must not enqueue, so the jobs enqueue from jobs/services as in ADR 0013. Batch several records per `RubyLLM.embed(array)` call in the re-embed task. Search queries embed the query text synchronously (one short call).

**Chunking.** Not for v1. One vector per item. Embed `subject + cleaned text` truncated to a budget of about 8k tokens (inside the 32k limit and the 8000/8191 of the hosted options), stripping quoted replies, signatures and HTML first. If a later need arises (long OCR documents where the match is deep in the text), add chunking at about 512-800 tokens with 10-15% overlap into a separate `chunk_index` column. Impact on #227: per-item vectors make document-to-document cosine comparison trivial; with chunks, dedup would need a chunk-set comparison, so keep dedup on one whole-document vector (plus the existing checksum for exact copies).

**Storage (#226) sketch.** `vec0` dimensions are fixed per table, and the model must be recorded per vector:

- `embeddings` (ActiveRecord table): `embeddable_type`, `embeddable_id`, `model` (string, e.g. `qwen3-embedding:0.6b`), `dimensions` (int), `content_digest` (SHA256 of the embedded text), `embedded_at`; unique on `[embeddable_type, embeddable_id, model]`.
- `embedding_vectors USING vec0(embedding float[1024] distance_metric=cosine)`, rowid = `embeddings.id`. Optionally a metadata column for the record kind, to filter Email vs Document inside KNN.
- Re-embed on model change: new model name means new rows; a rake task (`embeddings:reembed`) embeds everything under the new model (and a new `vec0` table if the dimension differs), then switches the configured `LlmModels.embedding` (Setting, then ENV, then default, as for the other models) and deletes old rows. Searches filter on the current model only. Skip unchanged content via `content_digest`.
- Add `LlmModels.embedding` following the existing accessor pattern.

**Distance metric.** Cosine (all candidates return normalised or near-normalised vectors, so L2 and dot product give the same ranking; cosine reads best as a threshold). sqlite-vec reports cosine distance, so similarity = 1 - distance.

**Quantization.** Float32 for now. At 50k items x 1024 dims the table is about 200 MB; int8 or bit quantization (supported by sqlite-vec) is a later option if size or latency matters.

**Dedup threshold (#227).** Start with cosine similarity 0.95 as a "near-duplicate" candidate range of 0.93-0.98 (re-scans and format changes of the same text usually land above 0.95; same-template but different documents, like two invoices from one sender, can score 0.9+ and are the main false-positive risk). This is a starting guess from general experience, not a measured value: it must be calibrated on real data per model (the threshold differs between models), kept configurable (`Setting`), and the first release should link and flag candidates for review rather than merge or hide automatically. Behaviour (merge, link, hide) is left to #227.

## Consequences

- A new `Ollama` base URL setting (shared with #208) and an Ollama service on dev and Hetzner, unless the runner-up is chosen.
- Changing model later is a re-embed job, not a migration; the `model` and `dimensions` columns make mixed state detectable.
- #226 and #227 can proceed once the model and dimension are accepted.

## Confirmed

Local Qwen3-Embedding-0.6B via Ollama; 1024 dims; languages English, German, Russian; no chunking in v1 (one vector per item).

## Unverified

Mistral's embedding multilingual quality and its own pricing page; OpenAI small's multilingual score; Ollama size of `qwen3-embedding:0.6b`; Ollama `dimensions` support; CPU latency on the Hetzner box and the 4 GB dev machine; whether Hetzner Inference serves an embedding model; `distance_metric=cosine` syntax on 0.1.9; thresholds.

## Sources

Accessed 2026-11-03 unless noted.

- RubyLLM 2.1.1 gem source and `models.json` (embedding.rb, providers/*, registry prices) under `/bundle`
- [Qwen3-Embedding-0.6B model card](https://huggingface.co/Qwen/Qwen3-Embedding-0.6B) (MTEB multilingual table; competitor scores from leaderboard dated 2025-05-24)
- [EmbeddingGemma-300m model card](https://huggingface.co/google/embeddinggemma-300m)
- [Ollama embeddinggemma-2](https://ollama.com/library/embeddinggemma-2) and [Ollama embedding models list](https://ollama.com/search?c=embedding)
- [bge-m3](https://huggingface.co/BAAI/bge-m3), [multilingual-e5-large-instruct](https://huggingface.co/intfloat/multilingual-e5-large-instruct), [nomic-embed-text-v2-moe](https://huggingface.co/nomic-ai/nomic-embed-text-v2-moe), [granite-embedding-278m-multilingual](https://huggingface.co/ibm-granite/granite-embedding-278m-multilingual)
- [Gemini embeddings docs](https://aistudio.google.com/docs/embeddings) and [Gemini pricing](https://aistudio.google.com/docs/pricing)
- [OpenAI text-embedding-3-small](https://developers.openai.com/api/docs/models/text-embedding-3-small)
- [Mistral text embeddings docs](https://docs.mistral.ai/studio/knowledge-rag/embeddings/text_embeddings), [Mistral code embeddings](https://docs.mistral.ai/capabilities/embeddings/code_embeddings); mistral-embed price from aggregators and the RubyLLM registry only
- [sqlite-vec vec0 docs](https://alexgarcia.xyz/sqlite-vec/features/vec0.html) and [v0.1.0 release benchmarks](https://alexgarcia.xyz/blog/2024/sqlite-vec-stable-release/index.html)
