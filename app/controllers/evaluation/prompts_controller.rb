
module Evaluation
  class PromptsController < ApplicationController
    def index
      @prompts = Prompt.order(:name, version: :desc)
    end

    def compare
      prompt_a, prompt_b = find_compare_prompts
      return redirect_to evaluation_prompts_path, alert: "Select two prompts to compare." unless prompt_a && prompt_b

      exp_a, exp_b = find_completed_experiments(prompt_a, prompt_b)
      return redirect_to evaluation_prompts_path, alert: "Both prompts need a completed experiment to compare." unless exp_a && exp_b

      redirect_to compare_evaluation_experiment_path(exp_a, candidate_id: exp_b.id)
    end

    private

    def find_compare_prompts
      [ Prompt.find_by(id: params[:prompt_a_id]), Prompt.find_by(id: params[:prompt_b_id]) ]
    end

    def find_completed_experiments(prompt_a, prompt_b)
      [
        prompt_a.experiments.where(status: :completed).order(created_at: :desc).first,
        prompt_b.experiments.where(status: :completed).order(created_at: :desc).first
      ]
    end
  end
end
