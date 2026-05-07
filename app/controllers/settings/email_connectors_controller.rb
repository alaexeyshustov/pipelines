module Settings
  class EmailConnectorsController < ApplicationController
    before_action :set_email_connector, only: %i[show edit update destroy test]

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

    private

    def set_email_connector
      @email_connector = EmailConnector.find(params[:id])
    end

    def email_connector_params
      params.require(:email_connector).permit(:name, :provider, :enabled, configuration: {})
    end
  end
end
