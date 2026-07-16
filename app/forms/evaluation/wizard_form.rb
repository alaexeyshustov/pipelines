
module Evaluation
  class WizardForm < ::BaseForm
    include SteepHacks

    WIZARD_STEPS = 4

    validate :all_steps_valid

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
      form = step_form(step)
      unless form.advance!(payload)
        form.errors.each { |e| errors.import(e) }
        return false
      end
      draft.advance!(step + 1, payload)
      true
    end

    def complete!
      CreateExperimentFromDraft.call(draft: draft)
    end

    def step_form(step)
      payload = draft.payload || empty_object
      case step
      when 1 then Wizard::Step1Form.new(draft_payload: payload)
      when 2 then Wizard::Step2Form.new(draft_payload: payload)
      when 3 then Wizard::Step3Form.new(draft_payload: payload, draft_token: @wizard_token)
      when 4 then Wizard::Step4Form.new(draft_payload: payload)
      end
    end

    private

    def all_steps_valid
      (1..WIZARD_STEPS).each do |s|
        form = step_form(s)
        next if form.valid?
        form.errors.each { |e| errors.import(e) }
      end
    end

    def draft
      @draft ||= WizardDraft.find_or_create_for_token(@wizard_token)
    end
  end
end
