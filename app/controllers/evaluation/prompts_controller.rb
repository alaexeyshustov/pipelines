# frozen_string_literal: true

module Evaluation
  class PromptsController < ApplicationController
    def index
      @prompts = Prompt.order(:name, version: :desc)
    end

    def compare
      prompt_a = Prompt.find_by(id: params[:prompt_a_id])
      prompt_b = Prompt.find_by(id: params[:prompt_b_id])

      unless prompt_a && prompt_b
        return redirect_to evaluation_prompts_path, alert: "Select two prompts to compare."
      end

      exp_a = prompt_a.experiments.where(status: :completed).order(created_at: :desc).first
      exp_b = prompt_b.experiments.where(status: :completed).order(created_at: :desc).first

      unless exp_a && exp_b
        return redirect_to evaluation_prompts_path, alert: "Both prompts need a completed experiment to compare."
      end

      redirect_to compare_evaluation_experiment_path(exp_a, candidate_id: exp_b.id)
    end
  end
end
