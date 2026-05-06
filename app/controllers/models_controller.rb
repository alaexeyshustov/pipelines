# frozen_string_literal: true

class ModelsController < ApplicationController
  def index
    @models = RubyLLM.models.all.sort_by { |m| [ m.provider.to_s, m.name ] }
  end

  def sync
    RubyLLM::Models.instance.refresh!
    redirect_to models_path, notice: "Models synced successfully."
  end
end
