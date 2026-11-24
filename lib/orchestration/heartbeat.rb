module Orchestration
  # Tells the run it is alive, so a run whose job died can be told apart from a long one (PipelineRun.blocking).
  # Executors call +beat+ per item of their loops; PipelineRunner stamps the run itself around each step.
  module Heartbeat
    INTERVAL = 1.minute

    # Stamps +heartbeat_at+ of the current run at most once per INTERVAL (no query otherwise); does nothing outside a run.
    def self.beat
      run = Current.pipeline_run
      return unless run

      last = run.heartbeat_at
      return if last && last > INTERVAL.ago # steep:ignore

      run.update_columns(heartbeat_at: Time.current)
    end
  end
end
