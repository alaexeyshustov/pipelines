# frozen_string_literal: true

class InterviewsController < ApplicationController
  include Paginable
  paginable sortable: %w[company job_title status applied_at],
            per_page: [ 10, 20, 50 ],
            default_sort: "applied_at"

  before_action :set_interview, only: [ :show, :edit, :update, :destroy ]

  def index
    @query = params[:q]
    session[:interviews_filters] = params.permit(:q, :sort, :direction, :per_page).to_h
    @pagy, @interviews = paginate(Interview.search(@query))
  end

  def show
  end

  def new
    @interview = Interview.new
  end

  def create
    @interview = Interview.new(interview_params)
    if @interview.save
      redirect_to interviews_index_with_filters, notice: "Interview record created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @interview.update(interview_params)
      redirect_to interviews_index_with_filters, notice: "Interview record updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @interview.destroy
    redirect_to interviews_index_with_filters, notice: "Interview record deleted."
  end

  def batch
    ids        = params[:ids]
    batch_action = params[:batch_action]

    result = Interviews::BatchService.new(ids: ids.to_a, batch_action: batch_action.to_s).call
    if result.csv?
      send_data result.csv, filename: "interviews_#{Date.today}.csv", type: "text/csv", disposition: "attachment"
    else
      redirect_to interviews_index_with_filters, **flash_for(result)
    end
  end

  def export_gist
    gist_id = params[:gist_id].to_s.strip

    result = Interviews::GistExportService.new(ids: params[:ids], gist_id: gist_id).call
    redirect_to interviews_index_with_filters, **flash_for(result)
  end

  private

  def interviews_index_with_filters
    interviews_path(session.fetch(:interviews_filters, {}))
  end

  def set_interview
    @interview = Interview.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def interview_params
    params.require(:interview).permit(
      :company, :job_title, :status,
      :applied_at, :rejected_at,
      :first_interview_at, :second_interview_at,
      :third_interview_at, :fourth_interview_at
    )
  end
end
