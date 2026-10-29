# ruby_llm-monitoring subscribes to every /ruby_llm/ notification and JSON-dumps
# the payload minus FILTERED_PAYLOAD_KEYS. Native RubyLLM::Evaluation events carry
# live Report/Trial objects (evaluation.ruby_llm, evaluation_trial.ruby_llm) whose
# serialization recurses without end, so filter those keys too.
Rails.application.config.to_prepare do
  subscriber = RubyLLM::Monitoring::EventSubscriber
  extra = %i[report trial]
  unless (extra - subscriber::FILTERED_PAYLOAD_KEYS).empty?
    keys = (subscriber::FILTERED_PAYLOAD_KEYS + extra).freeze
    subscriber.send(:remove_const, :FILTERED_PAYLOAD_KEYS)
    subscriber.const_set(:FILTERED_PAYLOAD_KEYS, keys)
  end
end
