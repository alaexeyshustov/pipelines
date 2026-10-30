module Orchestration
  # Imports pipelines from the hash produced by PipelineExporter (string keys, as JSON.parse returns).
  # All-or-nothing: the whole file runs in one transaction. Never raises for bad input.
  class PipelineImporter
    Result = Data.define(:pipelines, :errors)

    FORMAT = "pipeline_export".freeze
    KINDS = %w[agent service].freeze
    PIPELINE_KEYS = %w[name description cron_expression model initial_input_schema].freeze
    STEP_KEYS = %w[name enabled].freeze
    STEP_ACTION_KEYS = %w[output_key input_mapping].freeze
    ACTION_KEYS = %w[name description].freeze
    AGENT_KEYS = %w[name description model tools enabled prompt output_schema input_schema].freeze

    class ImportError < StandardError; end

    def self.call(data)
      new(data).call
    end

    def initialize(data)
      @data = data
    end

    def call
      pipelines = [] # : Array[Pipeline]
      ActiveRecord::Base.transaction do
        pipelines = import_all
      end
      Result.new(pipelines: pipelines, errors: [])
    rescue ImportError, ActiveRecord::ActiveRecordError => e
      Result.new(pipelines: [], errors: [ e.message ])
    end

    include Shape

    private

    def import_all
      root = hash!(@data, "File")
      raise ImportError, "Unsupported format: expected #{FORMAT.inspect}" unless root["format"] == FORMAT

      required_array!(root["pipelines"], "pipelines").each_with_index.map do |entry, index|
        import_pipeline(hash!(entry, "pipelines[#{index}]"))
      end
    end

    def import_pipeline(data)
      label = "pipeline #{data["name"].inspect}"
      pipeline = build_pipeline(data)
      save!(pipeline, label)

      array!(data["steps"], "#{label} steps").each_with_index do |step_data, index|
        import_step(pipeline, hash!(step_data, "#{label} steps[#{index}]"), index + 1, label)
      end
      report_mapping_errors(pipeline, label)
      pipeline
    end

    def build_pipeline(data)
      pipeline = Pipeline.new(slice(data, PIPELINE_KEYS))
      pipeline.name = unique_name(data["name"]) if data["name"].present?
      pipeline.enabled = false
      pipeline
    end

    def import_step(pipeline, data, position, parent_label)
      label = "#{parent_label} > step #{data["name"].inspect}"
      step = pipeline.steps.build(slice(data, STEP_KEYS).merge(position: position))
      save!(step, label)

      array!(data["step_actions"], "#{label} step_actions").each_with_index do |sa_data, index|
        import_step_action(step, hash!(sa_data, "#{label} step_actions[#{index}]"), index + 1, label)
      end
    end

    def import_step_action(step, data, position, parent_label)
      label = "#{parent_label} > step_action #{data["output_key"].inspect}"
      action = import_action(hash!(data["action"], "#{label} action"), label)
      step_action = StepAction.new(slice(data, STEP_ACTION_KEYS).merge(step: step, action: action, position: position))
      save!(step_action, label)
    end

    def import_action(data, parent_label)
      label = "#{parent_label} > action #{data["name"].inspect}"
      kind = data["kind"]
      raise ImportError, "#{label}: unknown kind #{kind.inspect}" unless kind.is_a?(String) && KINDS.include?(kind)

      action = Action.new(slice(data, ACTION_KEYS).merge(kind: kind))
      assign_executor(action, data, label)
      save!(action, label)
      action
    end

    def assign_executor(action, data, label)
      if action.kind == "agent"
        agent_data = data["agent"]
        action.agent_id = find_or_create_agent(hash!(agent_data, "#{label} agent"), label).id unless agent_data.nil?
      else
        action.agent_class = decode_keyword(data["agent_class"], label)
      end
    end

    def find_or_create_agent(data, parent_label)
      label = "#{parent_label} > agent #{data["name"].inspect}"
      existing = data["name"].is_a?(String) ? Agent.find_by(name: data["name"]) : nil
      return existing if existing

      array!(data["tools"], "#{label} tools")
      agent = Agent.new(slice(data, AGENT_KEYS))
      save!(agent, label)
      agent
    end

    def decode_keyword(keyword, label)
      keyword && AgentClassKeyword.decode(keyword.to_s)
    rescue AgentClassKeyword::UnknownKeyword => e
      raise ImportError, "#{label}: #{e.message}"
    end

    def report_mapping_errors(pipeline, label)
      issues = pipeline.validate_steps.flat_map(&:errors)
      return if issues.empty?

      raise ImportError, "#{label}: #{issues.map(&:message).join('; ')}"
    end

    def unique_name(name)
      base = name.to_s
      return base unless Pipeline.exists?(name: base)

      n = 2
      n += 1 while Pipeline.exists?(name: "#{base} (#{n})")
      "#{base} (#{n})"
    end

    def save!(record, label)
      return if record.save

      raise ImportError, "#{label}: #{record.errors.full_messages.join(', ')}"
    end
  end
end
