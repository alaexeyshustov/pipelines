
class ModelsController < ApplicationController
  include Paginable
  paginable per_page: [ 20, 50, 100 ]

  def index
    @query = params[:q].to_s
    models = RubyLLM.models.all.sort_by { |m| [ m.provider.to_s, m.name ] }
    models = models.select { |m| model_matches?(m, @query) } if @query.present?
    @pagy, @models = pagy(:offset, models, limit: @per_page)
  end

  def sync
    RubyLLM::Models.instance.refresh!
    redirect_to models_path, notice: "Models synced successfully."
  end

  private

  def model_matches?(model, query)
    q = query.downcase
    model.id.to_s.downcase.include?(q) ||
      model.display_name.to_s.downcase.include?(q) ||
      model.provider.to_s.downcase.include?(q)
  end
end
