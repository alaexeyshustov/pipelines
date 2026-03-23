# Schemas

- `application_mails` — one row per job email (date, provider, email_id, company, job_title, action)
- `interviews` — one row per company/job_title pair, tracking lifecycle status and interview dates
- `email_vectors` — sqlite-vec virtual table (vec0) storing 1536-dim float embeddings for RAG (**not yet wired into the workflow** — exists for future RAG use)

`EmailVector.search(embedding)` wraps the `vec0` KNN query. `SqliteVecExtension` in `config/initializers/sqlite_vec.rb` loads the extension on every connection.

Schema format is `:sql` (not `:ruby`) because `vec0` virtual tables cannot be expressed in Ruby schema DSL.

