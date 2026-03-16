CREATE TABLE IF NOT EXISTS "schema_migrations" ("version" varchar NOT NULL PRIMARY KEY);
CREATE TABLE IF NOT EXISTS "ar_internal_metadata" ("key" varchar NOT NULL PRIMARY KEY, "value" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE TABLE IF NOT EXISTS "application_mails" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "date" date NOT NULL, "provider" varchar NOT NULL, "email_id" varchar NOT NULL, "company" varchar, "job_title" varchar, "action" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE UNIQUE INDEX "index_application_mails_on_email_id" ON "application_mails" ("email_id") /*application='ApplicationPipeline'*/;
CREATE INDEX "index_application_mails_on_date" ON "application_mails" ("date") /*application='ApplicationPipeline'*/;
CREATE TABLE IF NOT EXISTS "interviews" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "company" varchar NOT NULL, "job_title" varchar NOT NULL, "status" varchar DEFAULT 'pending_reply', "applied_at" date, "rejected_at" date, "first_interview_at" date, "second_interview_at" date, "third_interview_at" date, "fourth_interview_at" date, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE UNIQUE INDEX "index_interviews_on_company_and_job_title" ON "interviews" ("company", "job_title") /*application='ApplicationPipeline'*/;
CREATE VIRTUAL TABLE email_vectors USING vec0(
  email_id TEXT PRIMARY KEY,
  embedding FLOAT[1536]
);
CREATE TABLE IF NOT EXISTS "email_vectors_info" (key text primary key, value any);
CREATE TABLE IF NOT EXISTS "email_vectors_chunks"(chunk_id INTEGER PRIMARY KEY AUTOINCREMENT,size INTEGER NOT NULL,validity BLOB NOT NULL,rowids BLOB NOT NULL);
CREATE TABLE IF NOT EXISTS "email_vectors_rowids"(rowid INTEGER PRIMARY KEY AUTOINCREMENT,id TEXT UNIQUE NOT NULL,chunk_id INTEGER,chunk_offset INTEGER);
CREATE TABLE IF NOT EXISTS "email_vectors_vector_chunks00"(rowid PRIMARY KEY,vectors BLOB NOT NULL);
INSERT INTO "schema_migrations" (version) VALUES
('20260316000003'),
('20260316000002'),
('20260316000001');

