# frozen_string_literal: true

module Evaluation
  # Raised by CreateExperimentFromDraft when the resolved agent has no active metrics.
  # The wizard guard in WizardForm#advance! prevents this in the normal flow; this error
  # is a defence-in-depth check for race conditions (metrics deactivated after step 2)
  # or direct API access that bypasses the wizard.
  class NoMetricsError < StandardError; end
end
