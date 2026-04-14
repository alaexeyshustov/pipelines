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
CREATE TABLE IF NOT EXISTS "models" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "model_id" varchar NOT NULL, "name" varchar NOT NULL, "provider" varchar NOT NULL, "family" varchar, "model_created_at" datetime(6), "context_window" integer, "max_output_tokens" integer, "knowledge_cutoff" date, "modalities" json DEFAULT '{}', "capabilities" json DEFAULT '[]', "pricing" json DEFAULT '{}', "metadata" json DEFAULT '{}', "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE UNIQUE INDEX "index_models_on_provider_and_model_id" ON "models" ("provider", "model_id") /*application='ApplicationPipeline'*/;
CREATE INDEX "index_models_on_provider" ON "models" ("provider") /*application='ApplicationPipeline'*/;
CREATE INDEX "index_models_on_family" ON "models" ("family") /*application='ApplicationPipeline'*/;
CREATE TABLE IF NOT EXISTS "chats" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "model_id" integer, CONSTRAINT "fk_rails_1835d93df1"
FOREIGN KEY ("model_id")
  REFERENCES "models" ("id")
);
CREATE INDEX "index_chats_on_model_id" ON "chats" ("model_id") /*application='ApplicationPipeline'*/;
CREATE TABLE IF NOT EXISTS "tool_calls" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "tool_call_id" varchar NOT NULL, "name" varchar NOT NULL, "thought_signature" text, "arguments" json DEFAULT '{}', "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "message_id" integer NOT NULL, CONSTRAINT "fk_rails_9c8daee481"
FOREIGN KEY ("message_id")
  REFERENCES "messages" ("id")
);
CREATE UNIQUE INDEX "index_tool_calls_on_tool_call_id" ON "tool_calls" ("tool_call_id") /*application='ApplicationPipeline'*/;
CREATE INDEX "index_tool_calls_on_name" ON "tool_calls" ("name") /*application='ApplicationPipeline'*/;
CREATE INDEX "index_tool_calls_on_message_id" ON "tool_calls" ("message_id") /*application='ApplicationPipeline'*/;
CREATE TABLE IF NOT EXISTS "messages" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "role" varchar NOT NULL, "content" text, "content_raw" json, "thinking_text" text, "thinking_signature" text, "thinking_tokens" integer, "input_tokens" integer, "output_tokens" integer, "cached_tokens" integer, "cache_creation_tokens" integer, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "chat_id" integer NOT NULL, "model_id" integer, "tool_call_id" integer, CONSTRAINT "fk_rails_c02b47ad97"
FOREIGN KEY ("model_id")
  REFERENCES "models" ("id")
, CONSTRAINT "fk_rails_0f670de7ba"
FOREIGN KEY ("chat_id")
  REFERENCES "chats" ("id")
, CONSTRAINT "fk_rails_552873cb52"
FOREIGN KEY ("tool_call_id")
  REFERENCES "tool_calls" ("id")
);
CREATE INDEX "index_messages_on_role" ON "messages" ("role") /*application='ApplicationPipeline'*/;
CREATE INDEX "index_messages_on_chat_id" ON "messages" ("chat_id") /*application='ApplicationPipeline'*/;
CREATE INDEX "index_messages_on_model_id" ON "messages" ("model_id") /*application='ApplicationPipeline'*/;
CREATE INDEX "index_messages_on_tool_call_id" ON "messages" ("tool_call_id") /*application='ApplicationPipeline'*/;
CREATE TABLE IF NOT EXISTS "steps" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "pipeline_id" integer NOT NULL, "name" varchar NOT NULL, "position" integer NOT NULL, "input_mapping" json, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "enabled" boolean DEFAULT TRUE NOT NULL /*application='ApplicationPipeline'*/, CONSTRAINT "fk_rails_bbcf3ea2ee"
FOREIGN KEY ("pipeline_id")
  REFERENCES "pipelines" ("id")
);
CREATE INDEX "index_steps_on_pipeline_id" ON "steps" ("pipeline_id") /*application='ApplicationPipeline'*/;
CREATE UNIQUE INDEX "index_steps_on_pipeline_id_and_position" ON "steps" ("pipeline_id", "position") /*application='ApplicationPipeline'*/;
CREATE TABLE IF NOT EXISTS "actions" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "name" varchar NOT NULL, "agent_class" varchar NOT NULL, "description" text, "model" varchar, "tools" json, "prompt" text, "params" json, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "output_schema" json /*application='ApplicationPipeline'*/, "schema_class" varchar /*application='ApplicationPipeline'*/);
CREATE TABLE IF NOT EXISTS "step_actions" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "step_id" integer NOT NULL, "action_id" integer NOT NULL, "position" integer NOT NULL, "params" json, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_d9cf618a2f"
FOREIGN KEY ("step_id")
  REFERENCES "steps" ("id")
, CONSTRAINT "fk_rails_0b2a35e398"
FOREIGN KEY ("action_id")
  REFERENCES "actions" ("id")
);
CREATE INDEX "index_step_actions_on_step_id" ON "step_actions" ("step_id") /*application='ApplicationPipeline'*/;
CREATE INDEX "index_step_actions_on_action_id" ON "step_actions" ("action_id") /*application='ApplicationPipeline'*/;
CREATE UNIQUE INDEX "index_step_actions_on_step_id_and_position" ON "step_actions" ("step_id", "position") /*application='ApplicationPipeline'*/;
CREATE TABLE IF NOT EXISTS "pipeline_runs" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "pipeline_id" integer NOT NULL, "status" varchar DEFAULT 'pending' NOT NULL, "triggered_by" varchar, "started_at" datetime(6), "finished_at" datetime(6), "error" text, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "initial_input" json /*application='ApplicationPipeline'*/, CONSTRAINT "fk_rails_7774d88070"
FOREIGN KEY ("pipeline_id")
  REFERENCES "pipelines" ("id")
);
CREATE INDEX "index_pipeline_runs_on_pipeline_id" ON "pipeline_runs" ("pipeline_id") /*application='ApplicationPipeline'*/;
CREATE INDEX "index_pipeline_runs_on_status" ON "pipeline_runs" ("status") /*application='ApplicationPipeline'*/;
CREATE INDEX "index_pipeline_runs_on_pipeline_id_and_created_at" ON "pipeline_runs" ("pipeline_id", "created_at") /*application='ApplicationPipeline'*/;
CREATE TABLE IF NOT EXISTS "pipelines" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "name" varchar NOT NULL, "description" text, "enabled" boolean DEFAULT TRUE NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "cron_expression" varchar, "model" varchar /*application='ApplicationPipeline'*/, "initial_input_schema" json /*application='ApplicationPipeline'*/);
CREATE INDEX "index_pipelines_on_enabled_and_cron_expression" ON "pipelines" ("enabled", "cron_expression") /*application='ApplicationPipeline'*/;
CREATE TABLE IF NOT EXISTS "ruby_llm_monitoring_events" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "allocations" integer, "cost" float, "cpu_time" float, "duration" float, "end" float, "gc_time" float, "idle_time" float, "name" varchar, "payload" json, "time" float, "transaction_id" varchar, "provider" varchar GENERATED ALWAYS AS (payload->>'provider') STORED, "model" varchar GENERATED ALWAYS AS (payload->>'model') STORED, "input_tokens" integer GENERATED ALWAYS AS (CAST(payload->>'input_tokens' AS INTEGER)) STORED, "output_tokens" integer GENERATED ALWAYS AS (CAST(payload->>'output_tokens' AS INTEGER)) STORED, "exception_class" varchar GENERATED ALWAYS AS (json_extract(payload, '$.exception[0]')) STORED, "exception_message" varchar GENERATED ALWAYS AS (json_extract(payload, '$.exception[1]')) STORED, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "thinking_tokens" integer GENERATED ALWAYS AS (CAST(payload->>'thinking_tokens' AS INTEGER)) STORED);
CREATE TABLE IF NOT EXISTS "action_runs" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "pipeline_run_id" integer NOT NULL, "step_action_id" integer NOT NULL, "status" varchar DEFAULT 'pending' NOT NULL, "input" json, "output" json, "error" text, "started_at" datetime(6), "finished_at" datetime(6), "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "chat_id" integer, CONSTRAINT "fk_rails_98c536e7ea"
FOREIGN KEY ("step_action_id")
  REFERENCES "step_actions" ("id")
, CONSTRAINT "fk_rails_e54391b086"
FOREIGN KEY ("pipeline_run_id")
  REFERENCES "pipeline_runs" ("id")
, CONSTRAINT "fk_rails_2f2096f1b1"
FOREIGN KEY ("chat_id")
  REFERENCES "chats" ("id")
);
CREATE INDEX "index_action_runs_on_pipeline_run_id" ON "action_runs" ("pipeline_run_id") /*application='ApplicationPipeline'*/;
CREATE INDEX "index_action_runs_on_step_action_id" ON "action_runs" ("step_action_id") /*application='ApplicationPipeline'*/;
CREATE INDEX "index_action_runs_on_status" ON "action_runs" ("status") /*application='ApplicationPipeline'*/;
CREATE INDEX "index_action_runs_on_chat_id" ON "action_runs" ("chat_id") /*application='ApplicationPipeline'*/;
CREATE TABLE IF NOT EXISTS "leva_datasets" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "name" varchar, "description" text, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE TABLE IF NOT EXISTS "leva_dataset_records" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "dataset_id" integer NOT NULL, "recordable_type" varchar NOT NULL, "recordable_id" integer NOT NULL, "actual_result" text, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_a0599aa621"
FOREIGN KEY ("dataset_id")
  REFERENCES "leva_datasets" ("id")
);
CREATE INDEX "index_leva_dataset_records_on_dataset_id" ON "leva_dataset_records" ("dataset_id") /*application='ApplicationPipeline'*/;
CREATE INDEX "index_leva_dataset_records_on_recordable" ON "leva_dataset_records" ("recordable_type", "recordable_id") /*application='ApplicationPipeline'*/;
CREATE TABLE IF NOT EXISTS "leva_prompts" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "name" varchar, "version" integer, "system_prompt" text, "user_prompt" text, "metadata" text, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE TABLE IF NOT EXISTS "leva_experiments" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "name" varchar, "description" text, "dataset_id" integer NOT NULL, "prompt_id" integer, "status" integer, "metadata" text, "runner_class" varchar, "evaluator_classes" text, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_067bfa5025"
FOREIGN KEY ("dataset_id")
  REFERENCES "leva_datasets" ("id")
, CONSTRAINT "fk_rails_4aa77a56d1"
FOREIGN KEY ("prompt_id")
  REFERENCES "leva_prompts" ("id")
);
CREATE INDEX "index_leva_experiments_on_dataset_id" ON "leva_experiments" ("dataset_id") /*application='ApplicationPipeline'*/;
CREATE INDEX "index_leva_experiments_on_prompt_id" ON "leva_experiments" ("prompt_id") /*application='ApplicationPipeline'*/;
CREATE TABLE IF NOT EXISTS "leva_runner_results" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "experiment_id" integer, "dataset_record_id" integer NOT NULL, "prompt_id" integer NOT NULL, "prompt_version" integer, "prediction" text, "runner_class" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_abd1d29b91"
FOREIGN KEY ("experiment_id")
  REFERENCES "leva_experiments" ("id")
, CONSTRAINT "fk_rails_bbc5ca9d18"
FOREIGN KEY ("dataset_record_id")
  REFERENCES "leva_dataset_records" ("id")
, CONSTRAINT "fk_rails_919dd5b17f"
FOREIGN KEY ("prompt_id")
  REFERENCES "leva_prompts" ("id")
);
CREATE INDEX "index_leva_runner_results_on_experiment_id" ON "leva_runner_results" ("experiment_id") /*application='ApplicationPipeline'*/;
CREATE INDEX "index_leva_runner_results_on_dataset_record_id" ON "leva_runner_results" ("dataset_record_id") /*application='ApplicationPipeline'*/;
CREATE INDEX "index_leva_runner_results_on_prompt_id" ON "leva_runner_results" ("prompt_id") /*application='ApplicationPipeline'*/;
CREATE TABLE IF NOT EXISTS "leva_evaluation_results" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "experiment_id" integer, "dataset_record_id" integer NOT NULL, "runner_result_id" integer NOT NULL, "evaluator_class" varchar NOT NULL, "score" float, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_54593eaaa5"
FOREIGN KEY ("experiment_id")
  REFERENCES "leva_experiments" ("id")
, CONSTRAINT "fk_rails_e225e3559f"
FOREIGN KEY ("dataset_record_id")
  REFERENCES "leva_dataset_records" ("id")
, CONSTRAINT "fk_rails_706698fcd9"
FOREIGN KEY ("runner_result_id")
  REFERENCES "leva_runner_results" ("id")
);
CREATE INDEX "index_leva_evaluation_results_on_experiment_id" ON "leva_evaluation_results" ("experiment_id") /*application='ApplicationPipeline'*/;
CREATE INDEX "index_leva_evaluation_results_on_dataset_record_id" ON "leva_evaluation_results" ("dataset_record_id") /*application='ApplicationPipeline'*/;
CREATE INDEX "index_leva_evaluation_results_on_runner_result_id" ON "leva_evaluation_results" ("runner_result_id") /*application='ApplicationPipeline'*/;
CREATE TABLE IF NOT EXISTS "leva_optimization_runs" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "dataset_id" integer NOT NULL, "prompt_id" integer, "status" varchar DEFAULT 'pending' NOT NULL, "current_step" varchar, "progress" integer DEFAULT 0 NOT NULL, "examples_processed" integer DEFAULT 0, "total_examples" integer, "prompt_name" varchar NOT NULL, "mode" varchar DEFAULT 'light' NOT NULL, "error_message" text, "metadata" json, "model" varchar, "optimizer" varchar DEFAULT 'bootstrap' NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_7f27bdc0a6"
FOREIGN KEY ("dataset_id")
  REFERENCES "leva_datasets" ("id")
, CONSTRAINT "fk_rails_b09005ac77"
FOREIGN KEY ("prompt_id")
  REFERENCES "leva_prompts" ("id")
);
CREATE INDEX "index_leva_optimization_runs_on_dataset_id" ON "leva_optimization_runs" ("dataset_id") /*application='ApplicationPipeline'*/;
CREATE INDEX "index_leva_optimization_runs_on_prompt_id" ON "leva_optimization_runs" ("prompt_id") /*application='ApplicationPipeline'*/;
CREATE INDEX "index_leva_optimization_runs_on_status" ON "leva_optimization_runs" ("status") /*application='ApplicationPipeline'*/;
INSERT INTO "schema_migrations" (version) VALUES
('20260414120027'),
('20260414120026'),
('20260414120025'),
('20260414120024'),
('20260414120023'),
('20260414120022'),
('20260414120021'),
('20260411074607'),
('20260410145544'),
('20260410145543'),
('20260403000002'),
('20260403000001'),
('20260402000004'),
('20260402000003'),
('20260402000002'),
('20260402000001'),
('20260330160511'),
('20260330154456'),
('20260330145327'),
('20260321000006'),
('20260321000005'),
('20260321000004'),
('20260321000003'),
('20260321000002'),
('20260321000001'),
('20260316160148'),
('20260316160147'),
('20260316160146'),
('20260316160145'),
('20260316160144'),
('20260316000003'),
('20260316000002'),
('20260316000001');

