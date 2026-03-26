# frozen_string_literal: true

class InterviewsController < ApplicationController
  before_action :set_interview, only: [ :show, :edit, :update, :destroy ]

  def index
    @pagy, @interviews = pagy(Interview.order(:company, :job_title))
  end

  def show
  end

  def new
    @interview = Interview.new
  end

  def create
    @interview = Interview.new(interview_params)
    if @interview.save
      redirect_to interviews_path, notice: "Interview record created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @interview.update(interview_params)
      redirect_to interviews_path, notice: "Interview record updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @interview.destroy
    redirect_to interviews_path, notice: "Interview record deleted."
  end

  private

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
