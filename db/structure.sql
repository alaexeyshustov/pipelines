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
CREATE TABLE IF NOT EXISTS "orchestration_pipeline_runs" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "pipeline_id" integer NOT NULL, "status" varchar DEFAULT 'pending' NOT NULL, "triggered_by" varchar, "started_at" datetime(6), "finished_at" datetime(6), "error" text, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "initial_input" json /*application='ApplicationPipeline'*/, CONSTRAINT "fk_rails_7774d88070"
FOREIGN KEY ("pipeline_id")
  REFERENCES "orchestration_pipelines" ("id")
);
CREATE TABLE IF NOT EXISTS "orchestration_pipelines" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "name" varchar NOT NULL, "description" text, "enabled" boolean DEFAULT TRUE NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "cron_expression" varchar, "model" varchar /*application='ApplicationPipeline'*/, "initial_input_schema" json /*application='ApplicationPipeline'*/);
CREATE TABLE IF NOT EXISTS "ruby_llm_monitoring_events" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "allocations" integer, "cost" float, "cpu_time" float, "duration" float, "end" float, "gc_time" float, "idle_time" float, "name" varchar, "payload" json, "time" float, "transaction_id" varchar, "provider" varchar GENERATED ALWAYS AS (payload->>'provider') STORED, "model" varchar GENERATED ALWAYS AS (payload->>'model') STORED, "input_tokens" integer GENERATED ALWAYS AS (CAST(payload->>'input_tokens' AS INTEGER)) STORED, "output_tokens" integer GENERATED ALWAYS AS (CAST(payload->>'output_tokens' AS INTEGER)) STORED, "exception_class" varchar GENERATED ALWAYS AS (json_extract(payload, '$.exception[0]')) STORED, "exception_message" varchar GENERATED ALWAYS AS (json_extract(payload, '$.exception[1]')) STORED, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "thinking_tokens" integer GENERATED ALWAYS AS (CAST(payload->>'thinking_tokens' AS INTEGER)) STORED);
CREATE TABLE IF NOT EXISTS "orchestration_action_runs" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "pipeline_run_id" integer NOT NULL, "step_action_id" integer NOT NULL, "status" varchar DEFAULT 'pending' NOT NULL, "input" json, "output" json, "error" text, "started_at" datetime(6), "finished_at" datetime(6), "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "chat_id" integer, "agent_snapshot" json /*application='ApplicationPipeline'*/, "error_details" json /*application='ApplicationPipeline'*/, CONSTRAINT "fk_rails_98c536e7ea"
FOREIGN KEY ("step_action_id")
  REFERENCES "orchestration_step_actions" ("id")
, CONSTRAINT "fk_rails_e54391b086"
FOREIGN KEY ("pipeline_run_id")
  REFERENCES "orchestration_pipeline_runs" ("id")
, CONSTRAINT "fk_rails_2f2096f1b1"
FOREIGN KEY ("chat_id")
  REFERENCES "chats" ("id")
);
CREATE TABLE IF NOT EXISTS "evaluation_datasets" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "name" varchar, "description" text, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE TABLE IF NOT EXISTS "evaluation_prompts" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "name" varchar, "version" integer, "system_prompt" text, "user_prompt" text, "metadata" text, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "output_schema" json /*application='ApplicationPipeline'*/);
CREATE TABLE IF NOT EXISTS "evaluation_experiments" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "name" varchar, "description" text, "dataset_id" integer NOT NULL, "prompt_id" integer, "status" integer, "metadata" text, "runner_class" varchar, "evaluator_classes" text, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "sample_model" varchar /*application='ApplicationPipeline'*/, "evaluation_model" varchar /*application='ApplicationPipeline'*/, CONSTRAINT "fk_rails_067bfa5025"
FOREIGN KEY ("dataset_id")
  REFERENCES "evaluation_datasets" ("id")
, CONSTRAINT "fk_rails_4aa77a56d1"
FOREIGN KEY ("prompt_id")
  REFERENCES "evaluation_prompts" ("id")
);
CREATE TABLE IF NOT EXISTS "evaluation_metrics" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "agent_name" varchar NOT NULL, "name" varchar NOT NULL, "description" text NOT NULL, "weight" decimal DEFAULT 1.0 NOT NULL, "active" boolean DEFAULT TRUE NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE UNIQUE INDEX "index_evaluation_metrics_on_agent_name_and_name" ON "evaluation_metrics" ("agent_name", "name") /*application='ApplicationPipeline'*/;
CREATE TABLE IF NOT EXISTS "evaluation_justifications" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "evaluation_result_id" integer NOT NULL, "metric_name" varchar NOT NULL, "justification" text NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_517f4d40a2"
FOREIGN KEY ("evaluation_result_id")
  REFERENCES "evaluation_evaluation_results" ("id")
);
CREATE INDEX "index_evaluation_justifications_on_evaluation_result_id" ON "evaluation_justifications" ("evaluation_result_id") /*application='ApplicationPipeline'*/;
CREATE TABLE IF NOT EXISTS "orchestration_agents" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "name" varchar NOT NULL, "description" text, "model" varchar, "tools" json DEFAULT '[]', "enabled" boolean DEFAULT TRUE NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "prompt" text /*application='ApplicationPipeline'*/, "params" json DEFAULT '{}' NOT NULL /*application='ApplicationPipeline'*/, "output_schema" json /*application='ApplicationPipeline'*/);
CREATE UNIQUE INDEX "index_orchestration_agents_on_name" ON "orchestration_agents" ("name") /*application='ApplicationPipeline'*/;
CREATE TABLE IF NOT EXISTS "email_connectors" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "name" varchar NOT NULL, "provider" varchar NOT NULL, "configuration" text, "enabled" boolean DEFAULT TRUE NOT NULL, "last_connected_at" datetime(6), "status" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE TABLE IF NOT EXISTS "orchestration_step_actions" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "step_id" integer NOT NULL, "action_id" integer NOT NULL, "position" integer NOT NULL, "params" json, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "input_mapping" json, "output_key" varchar NOT NULL, CONSTRAINT "fk_rails_0b2a35e398"
FOREIGN KEY ("action_id")
  REFERENCES "orchestration_actions" ("id")
, CONSTRAINT "fk_rails_d9cf618a2f"
FOREIGN KEY ("step_id")
  REFERENCES "orchestration_steps" ("id")
);
CREATE TABLE IF NOT EXISTS "orchestration_steps" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "pipeline_id" integer NOT NULL, "name" varchar NOT NULL, "position" integer NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "enabled" boolean DEFAULT TRUE NOT NULL, CONSTRAINT "fk_rails_bbcf3ea2ee"
FOREIGN KEY ("pipeline_id")
  REFERENCES "orchestration_pipelines" ("id")
);
CREATE TABLE IF NOT EXISTS "evaluation_wizard_drafts" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "session_token" varchar NOT NULL, "step" integer DEFAULT 1 NOT NULL, "payload" json, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE UNIQUE INDEX "index_evaluation_wizard_drafts_on_session_token" ON "evaluation_wizard_drafts" ("session_token") /*application='ApplicationPipeline'*/;
CREATE INDEX "index_evaluation_experiments_on_prompt_id" ON "evaluation_experiments" ("prompt_id") /*application='ApplicationPipeline'*/;
CREATE INDEX "index_evaluation_experiments_on_dataset_id" ON "evaluation_experiments" ("dataset_id") /*application='ApplicationPipeline'*/;
CREATE INDEX "index_evaluation_prompts_on_name" ON "evaluation_prompts" ("name") /*application='ApplicationPipeline'*/;
CREATE TABLE IF NOT EXISTS "orchestration_actions" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "name" varchar NOT NULL, "agent_class" varchar, "description" text, "params" json, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "kind" varchar DEFAULT 'service' NOT NULL, "agent_id" integer, CONSTRAINT "fk_rails_951418a714"
FOREIGN KEY ("agent_id")
  REFERENCES "orchestration_agents" ("id")
);
CREATE INDEX "index_orchestration_pipelines_on_enabled_and_cron_expression" ON "orchestration_pipelines" ("enabled", "cron_expression") /*application='ApplicationPipeline'*/;
CREATE INDEX "idx_on_pipeline_id_created_at_7642cfe1dd" ON "orchestration_pipeline_runs" ("pipeline_id", "created_at") /*application='ApplicationPipeline'*/;
CREATE INDEX "index_orchestration_pipeline_runs_on_status" ON "orchestration_pipeline_runs" ("status") /*application='ApplicationPipeline'*/;
CREATE INDEX "index_orchestration_pipeline_runs_on_pipeline_id" ON "orchestration_pipeline_runs" ("pipeline_id") /*application='ApplicationPipeline'*/;
CREATE UNIQUE INDEX "index_orchestration_steps_on_pipeline_id_and_position" ON "orchestration_steps" ("pipeline_id", "position") /*application='ApplicationPipeline'*/;
CREATE INDEX "index_orchestration_steps_on_pipeline_id" ON "orchestration_steps" ("pipeline_id") /*application='ApplicationPipeline'*/;
CREATE INDEX "index_orchestration_actions_on_agent_id" ON "orchestration_actions" ("agent_id") /*application='ApplicationPipeline'*/;
CREATE INDEX "index_orchestration_actions_on_agent_class" ON "orchestration_actions" ("agent_class") /*application='ApplicationPipeline'*/;
CREATE UNIQUE INDEX "index_orchestration_step_actions_on_step_id_and_output_key" ON "orchestration_step_actions" ("step_id", "output_key") /*application='ApplicationPipeline'*/;
CREATE UNIQUE INDEX "index_orchestration_step_actions_on_step_id_and_position" ON "orchestration_step_actions" ("step_id", "position") /*application='ApplicationPipeline'*/;
CREATE INDEX "index_orchestration_step_actions_on_action_id" ON "orchestration_step_actions" ("action_id") /*application='ApplicationPipeline'*/;
CREATE INDEX "index_orchestration_step_actions_on_step_id" ON "orchestration_step_actions" ("step_id") /*application='ApplicationPipeline'*/;
CREATE INDEX "index_orchestration_action_runs_on_chat_id" ON "orchestration_action_runs" ("chat_id") /*application='ApplicationPipeline'*/;
CREATE INDEX "index_orchestration_action_runs_on_status" ON "orchestration_action_runs" ("status") /*application='ApplicationPipeline'*/;
CREATE INDEX "index_orchestration_action_runs_on_step_action_id" ON "orchestration_action_runs" ("step_action_id") /*application='ApplicationPipeline'*/;
CREATE INDEX "index_orchestration_action_runs_on_pipeline_run_id" ON "orchestration_action_runs" ("pipeline_run_id") /*application='ApplicationPipeline'*/;
CREATE TABLE IF NOT EXISTS "settings" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "key" varchar NOT NULL, "value" varchar NOT NULL, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE UNIQUE INDEX "index_settings_on_key" ON "settings" ("key") /*application='ApplicationPipeline'*/;
CREATE TABLE IF NOT EXISTS "evaluation_dataset_samples" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "dataset_id" integer NOT NULL, "input" json NOT NULL, "expected_tool_calls" json, "source_run_id" integer, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_7b805cc745"
FOREIGN KEY ("dataset_id")
  REFERENCES "evaluation_datasets" ("id")
);
CREATE INDEX "index_evaluation_dataset_samples_on_dataset_id" ON "evaluation_dataset_samples" ("dataset_id") /*application='ApplicationPipeline'*/;
CREATE UNIQUE INDEX "index_eval_dataset_samples_on_dataset_and_source_run" ON "evaluation_dataset_samples" ("dataset_id", "source_run_id") WHERE source_run_id IS NOT NULL /*application='ApplicationPipeline'*/;
CREATE TABLE IF NOT EXISTS "evaluation_samples" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "experiment_id" integer NOT NULL, "dataset_sample_id" integer NOT NULL, "prompt_id" integer NOT NULL, "tool_calls" json, "output" text, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_b9ea01d6cf"
FOREIGN KEY ("experiment_id")
  REFERENCES "evaluation_experiments" ("id")
, CONSTRAINT "fk_rails_bd05e89dc1"
FOREIGN KEY ("dataset_sample_id")
  REFERENCES "evaluation_dataset_samples" ("id")
, CONSTRAINT "fk_rails_2152db8e6b"
FOREIGN KEY ("prompt_id")
  REFERENCES "evaluation_prompts" ("id")
);
CREATE INDEX "index_evaluation_samples_on_experiment_id" ON "evaluation_samples" ("experiment_id") /*application='ApplicationPipeline'*/;
CREATE INDEX "index_evaluation_samples_on_dataset_sample_id" ON "evaluation_samples" ("dataset_sample_id") /*application='ApplicationPipeline'*/;
CREATE INDEX "index_evaluation_samples_on_prompt_id" ON "evaluation_samples" ("prompt_id") /*application='ApplicationPipeline'*/;
CREATE TABLE IF NOT EXISTS "evaluation_evaluation_results" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "experiment_id" integer, "evaluator_class" varchar NOT NULL, "score" float, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL, "dataset_sample_id" integer, "sample_id" integer, CONSTRAINT "fk_rails_6a68e87f09"
FOREIGN KEY ("dataset_sample_id")
  REFERENCES "evaluation_dataset_samples" ("id")
, CONSTRAINT "fk_rails_abd844afa6"
FOREIGN KEY ("experiment_id")
  REFERENCES "evaluation_experiments" ("id")
, CONSTRAINT "fk_rails_bf5da70aa5"
FOREIGN KEY ("sample_id")
  REFERENCES "evaluation_samples" ("id")
);
CREATE INDEX "index_evaluation_evaluation_results_on_experiment_id" ON "evaluation_evaluation_results" ("experiment_id") /*application='ApplicationPipeline'*/;
CREATE INDEX "index_evaluation_evaluation_results_on_dataset_sample_id" ON "evaluation_evaluation_results" ("dataset_sample_id") /*application='ApplicationPipeline'*/;
CREATE INDEX "index_evaluation_evaluation_results_on_sample_id" ON "evaluation_evaluation_results" ("sample_id") /*application='ApplicationPipeline'*/;
INSERT INTO "schema_migrations" (version) VALUES
('20260521000005'),
('20260521000004'),
('20260521000003'),
('20260521000002'),
('20260521000001'),
('20260519000002'),
('20260519000001'),
('20260516212546'),
('20260516185423'),
('20260514000002'),
('20260514000001'),
('20260513143500'),
('20260512110721'),
('20260512110713'),
('20260510120000'),
('20260507091027'),
('20260507091026'),
('20260507091025'),
('20260507091024'),
('20260507091023'),
('20260507091022'),
('20260507091021'),
('20260507091020'),
('20260507091019'),
('20260507091018'),
('20260507091017'),
('20260506143458'),
('20260506133642'),
('20260506000001'),
('20260504140000'),
('20260504130000'),
('20260504120000'),
('20260503170000'),
('20260503160000'),
('20260503140000'),
('20260503133626'),
('20260429112350'),
('20260427135859'),
('20260427000001'),
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

