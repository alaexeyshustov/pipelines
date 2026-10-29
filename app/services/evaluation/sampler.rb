module Evaluation
  # Runs the agent under test through a native RubyLLM::Evaluation (evaluator disabled:
  # sampling only) and persists the captured evidence as an Evaluation::Sample.
  # Write tools are replaced by a sentinel so sampling never mutates data.
  class Sampler
    WRITE_BLOCKED_SENTINEL = "[write tool blocked during sampling]"

    def self.call(experiment:, dataset_sample:, prompt:)
      new(experiment: experiment, dataset_sample: dataset_sample, prompt: prompt).call
    end

    def initialize(experiment:, dataset_sample:, prompt:)
      @experiment     = experiment
      @dataset_sample = dataset_sample
      @prompt         = prompt
    end

    def call
      test_case = Evaluation::DatasetCases.for_sample(@dataset_sample)
      trial     = task_class.run(dataset: [ test_case ]).trials.first # : RubyLLM::Evaluation::Trial
      error     = trial.error
      raise error if error

      persist_sample(trial)
    end

    private

    # RubyLLM instantiates the evaluation with no arguments, so the per-call
    # agent factory is closed over by an anonymous subclass.
    def task_class # steep:ignore:start
      factory = -> { build_agent }
      Class.new(RubyLLM::Evaluation) do
        evaluator false

        define_method(:perform) do |input|
          agent = factory.call
          agent.ask(input.to_json)
          agent
        end
      end
    end # steep:ignore:end

    def build_agent
      Orchestration::SamplingGateway.build(
        agent_name:      @experiment.agent_name,
        pipeline_model:  @experiment.sample_model,
        prompt_override: @prompt&.system_prompt,
        tool_transform:  ->(tools) { wrap_write_tools(tools) } # steep:ignore
      )
    end

    def persist_sample(trial)
      output = trial.output
      Evaluation::Sample.create!(
        experiment_id:     @experiment.id,
        dataset_sample_id: @dataset_sample.id,
        prompt_id:         @prompt&.id,
        tool_calls:        tool_calls_from(trial.evidence&.deep_stringify_keys),
        output:            output.is_a?(String) ? output : output.to_json
      )
    end

    # Pairs each tool call (assistant messages) with its result (tool messages)
    # from the native evidence, in call order.
    def tool_calls_from(evidence) # steep:ignore:start
      messages = Array(evidence && evidence["messages"])
      calls = index_calls(messages)
      messages.filter_map do |msg|
        call = calls[msg["tool_call_id"]] if msg["role"].to_s == "tool"
        next unless call

        { "tool_name" => call["name"], "arguments" => call["arguments"], "result" => msg["content"].to_s }
      end
    end

    def index_calls(messages)
      messages.flat_map { |msg| (msg["tool_calls"] || {}).values }.index_by { |call| call["id"] }
    end # steep:ignore:end

    def wrap_write_tools(tool_classes)
      tool_classes.map do |tool_class|
        next tool_class if tool_class.respond_to?(:readonly?) && tool_class.readonly? # steep:ignore

        block_write_tool(tool_class)
      end
    end

    def block_write_tool(tool_class)
      sentinel = WRITE_BLOCKED_SENTINEL
      # steep:ignore:start
      Class.new(tool_class) do
        define_method(:execute) do |**kwargs|
          Rails.logger.info("Sampler: blocked write tool #{name} (#{kwargs.keys.inspect})")
          sentinel
        end
      end # : singleton(RubyLLM::Tool)
      # steep:ignore:end
    end
  end
end
