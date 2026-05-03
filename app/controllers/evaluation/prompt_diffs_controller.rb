# frozen_string_literal: true

module Evaluation
  class PromptDiffsController < ApplicationController
    def show
      @prompt = Orchestration::Prompt.find(params[:id])
      @other_version = Orchestration::Prompt.where(name: @prompt.name).where.not(id: @prompt.id).order(version: :desc, id: :desc).first
    end
  end
end
