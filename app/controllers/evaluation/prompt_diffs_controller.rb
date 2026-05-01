# frozen_string_literal: true

module Evaluation
  class PromptDiffsController < ApplicationController
    def show
      @prompt = Leva::Prompt.find(params[:id])
      @other_version = Leva::Prompt.where(name: @prompt.name).where.not(id: @prompt.id).order(version: :desc, id: :desc).first
    end
  end
end
