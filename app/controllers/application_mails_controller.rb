# frozen_string_literal: true

class ApplicationMailsController < ApplicationController
  before_action :set_mail, only: [ :show, :edit, :update, :destroy ]

  def index
    @pagy, @mails = pagy(ApplicationMail.order(date: :desc))
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
