# frozen_string_literal: true

class ApplicationMailsController < ApplicationController
  include Paginable
  paginable sortable: %w[date provider company job_title action],
            per_page: [ 20, 50, 100 ],
            default_sort: "date"

  before_action :set_mail, only: [ :show, :edit, :update, :destroy ]

  def index
    @query = params[:q]
    @pagy, @mails = paginate(ApplicationMail.search(@query))
  end

  def show
  end

  def new
    @mail = ApplicationMail.new
  end

  def create
    @mail = ApplicationMail.new(mail_params)
    if @mail.save
      redirect_to application_mails_path, notice: "Email record created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @mail.update(mail_params)
      redirect_to application_mails_path, notice: "Email record updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @mail.destroy
    redirect_to application_mails_path, notice: "Email record deleted."
  end

  def batch
    ids = params[:ids]
    if ids.blank?
      redirect_back_or_to application_mails_path, alert: "No records selected."
      return
    end

    result = ApplicationMails::BatchService.new(ids: ids, batch_action: params[:batch_action]).call
    redirect_back_or_to application_mails_path,
                         **(result.ok? ? { notice: result.message } : { alert: result.message })
  end

  private

  def set_mail
    @mail = ApplicationMail.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def mail_params
    params.require(:application_mail).permit(:date, :provider, :email_id, :company, :job_title, :action)
  end
end
