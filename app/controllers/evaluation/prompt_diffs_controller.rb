# frozen_string_literal: true

module Evaluation
  class PromptDiffsController < ApplicationController
    def show
      @prompt = Evaluation::Prompt.find(params[:id].to_i)
      @other_version = Evaluation::Prompt.other_versions_for(@prompt.name, excluding_id: @prompt.id).first
    end
  end
end
