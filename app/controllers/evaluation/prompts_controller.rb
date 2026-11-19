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

    def activate
      prompt = Prompt.find(params[:id])
      unless prompt.activatable?
        return redirect_to evaluation_prompts_path, alert: "#{prompt.name} #{prompt.label} needs a completed experiment before it can be activated."
      end

      prompt.activate!
      redirect_to evaluation_prompts_path, notice: "#{prompt.label} activated for #{prompt.name}."
    end

    def deactivate
      prompt = Prompt.find(params[:id])
      if prompt.active?
        prompt.deactivate!
        redirect_to evaluation_prompts_path, notice: "#{prompt.name} now uses the agent default prompt."
      else
        redirect_to evaluation_prompts_path, notice: "#{prompt.name} #{prompt.label} was not active."
      end
    end

    private

    def find_compare_prompts
      ids = [ params[:prompt_a_id].to_s, params[:prompt_b_id].to_s ]
      prompts = Prompt.where(id: ids).index_by { |prompt| prompt.id.to_s }
      prompts.values_at(*ids)
    end

    def find_completed_experiments(prompt_a, prompt_b)
      [
        prompt_a.experiments.where(status: :completed).order(created_at: :desc).first,
        prompt_b.experiments.where(status: :completed).order(created_at: :desc).first
      ]
    end
  end
end
