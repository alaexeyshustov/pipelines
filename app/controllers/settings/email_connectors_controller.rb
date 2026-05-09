module Settings
  class EmailConnectorsController < ApplicationController
    before_action :set_email_connector, only: %i[show edit update destroy test setup]

    def index
      @email_connectors = EmailConnector.all
    end

    def show
    end

    def new
      @email_connector = EmailConnector.new
    end

    def edit
    end

    def create
      @email_connector = EmailConnector.new(email_connector_params)

      if @email_connector.save
        redirect_to settings_email_connectors_path, notice: "Email connector was successfully created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @email_connector.update(email_connector_params)
        redirect_to settings_email_connectors_path, notice: "Email connector was successfully updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @email_connector.destroy
      redirect_to settings_email_connectors_path, notice: "Email connector was successfully destroyed."
    end

    def test
      result = @email_connector.test_connection
      if result[:success]
        redirect_to settings_email_connectors_path, notice: "Connection successful!"
      else
        redirect_to settings_email_connectors_path, alert: "Connection failed: #{result[:error]}"
      end
    end

    def setup
      auth = Emails::GmailAuth.new(
        credentials_path: @email_connector.configuration["credentials_path"],
        token_path: @email_connector.configuration["token_path"],
        scope: Emails::Adapters::GmailAdapter::SCOPE
      )
      session[:oauth_connector_id] = @email_connector.id
      redirect_to auth.authorization_url(callback_uri: oauth_callback_settings_email_connectors_url),
                  allow_other_host: true
    rescue Errno::ENOENT => e
      redirect_to edit_settings_email_connector_path(@email_connector),
                  alert: "Credentials file not found: #{e.message}. Please check the Credentials JSON Path."
    end

    def oauth_callback
      connector_id = session.delete(:oauth_connector_id)
      unless connector_id
        redirect_to settings_email_connectors_path, alert: "OAuth session expired. Please try again."
        return
      end

      connector = EmailConnector.find(connector_id)
      callback_uri = oauth_callback_settings_email_connectors_url
      auth = Emails::GmailAuth.new(
        credentials_path: connector.configuration["credentials_path"],
        token_path: connector.configuration["token_path"],
        scope: Emails::Adapters::GmailAdapter::SCOPE
      )
      auth.exchange_code(code: params[:code], callback_uri:)

      redirect_to edit_settings_email_connector_path(connector), notice: "Gmail connected successfully."
    rescue StandardError => e
      redirect_to edit_settings_email_connector_path(connector), alert: "OAuth failed: #{e.message}"
    end

    private

    def set_email_connector
      @email_connector = EmailConnector.find(params[:id])
    end

    def email_connector_params
      params.require(:email_connector).permit(:name, :provider, :enabled, configuration: {})
    end
  end
end
