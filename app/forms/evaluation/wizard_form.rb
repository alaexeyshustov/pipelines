# frozen_string_literal: true

module Evaluation
  class WizardForm
    include ActiveModel::Validations

    WIZARD_STEPS = 4

    validate :dataset_selected

    def initialize(wizard_token:, step_param: nil)
      @wizard_token = wizard_token
      @step_param = step_param
    end

    def step
      (@step_param || draft.step).to_i.clamp(1, WIZARD_STEPS)
    end

    def complete?
      step >= WIZARD_STEPS
    end

    def advance!(step, payload)
      draft.advance!(step + 1, payload)
    end

    def complete!
      CreateExperimentFromDraft.call(draft: draft)
    end

    def step_form(step)
      payload = draft.payload || {}
      case step
      when 1 then Wizard::Step1Form.new(draft_payload: payload)
      when 2 then Wizard::Step2Form.new(draft_payload: payload)
      when 3 then Wizard::Step3Form.new(draft_payload: payload, draft_token: @wizard_token)
      when 4 then Wizard::Step4Form.new(draft_payload: payload)
      end
    end

    private

    def dataset_selected
      errors.add(:dataset, "must be selected") if (draft.payload || {})["dataset_id"].blank?
    end

    def draft
      @draft ||= WizardDraft.find_or_create_for_token(@wizard_token)
    end
  end
end
