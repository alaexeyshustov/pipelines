module Orchestration
  # The pipeline run being executed, for code deep inside an executor that has no run at hand (Heartbeat). Isolated
  # per fiber, and executors run inside Async tasks, so PipelineRunner sets it inside each task.
  class Current < ActiveSupport::CurrentAttributes
    attribute :pipeline_run
  end
end
