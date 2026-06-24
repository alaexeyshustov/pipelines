# frozen_string_literal: true

module Orchestration
  class NewStepComponentPreview < ViewComponent::Preview
    def default
      pipeline = Orchestration::Pipeline.new(id: 1, name: "Demo Pipeline")
      render(Orchestration::NewStepComponent.new(pipeline: pipeline))
    end
  end
end
