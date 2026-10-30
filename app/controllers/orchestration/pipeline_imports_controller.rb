module Orchestration
  class PipelineImportsController < ApplicationController
    def create
      form = Orchestration::PipelineImportForm.new(file: params[:file])

      if form.save
        names = form.pipelines.map(&:name).to_sentence
        redirect_to orchestration_pipelines_path, notice: "Imported (disabled): #{names}."
      else
        redirect_to orchestration_pipelines_path, alert: form.errors.full_messages.to_sentence
      end
    end
  end
end
