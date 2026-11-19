# ruby_llm-monitoring subscribes to every /ruby_llm/ notification and JSON-dumps
# the payload minus FILTERED_PAYLOAD_KEYS. Native RubyLLM::Evaluation events carry
# live Report/Trial objects (evaluation.ruby_llm, evaluation_trial.ruby_llm) whose
# serialization recurses without end, so filter those keys too.
Rails.application.config.to_prepare do
  # The gem's controllers inherit from ActionController::Base (no base_controller_class in 0.4.0),
  # so they join the app's login (GH #255) here.
  RubyLLM::Monitoring::ApplicationController.include Authentication

  subscriber = RubyLLM::Monitoring::EventSubscriber
  extra = %i[report trial]
  unless (extra - subscriber::FILTERED_PAYLOAD_KEYS).empty?
    keys = (subscriber::FILTERED_PAYLOAD_KEYS + extra).freeze
    subscriber.send(:remove_const, :FILTERED_PAYLOAD_KEYS)
    subscriber.const_set(:FILTERED_PAYLOAD_KEYS, keys)
  end
end
