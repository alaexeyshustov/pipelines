module Settings
  class EmailConnectorsController < ApplicationController
    # Errors whose message can quote the Gmail credentials file (see #log_setup_failure).
    FILE_QUOTING_ERRORS = [ Google::Auth::InitializationError, MultiJson::ParseError, JSON::ParserError ].freeze

    before_action :set_email_connector, only: %i[edit update destroy test setup]
    before_action :require_gmail_connector, only: :setup

    def index
      @email_connectors = EmailConnector.all
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
        render :new, status: :unprocessable_content
      end
    end

    def update
      if @email_connector.update(email_connector_params)
        redirect_to settings_email_connectors_path, notice: "Email connector was successfully updated."
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @email_connector.destroy
      redirect_to settings_email_connectors_path, notice: "Email connector was successfully destroyed."
    end

    def test
      result = Emails::TestConnectionService.call(connector: @email_connector)
      if result.success?
        redirect_to settings_email_connectors_path, notice: "Connection successful!"
      else
        redirect_to settings_email_connectors_path, alert: "Connection failed: #{result.error}"
      end
    end

    # A missing, malformed (googleauth >= 1.17 wraps the parser error in InitializationError) or unreadable credentials
    # file gets a generic alert.
    def setup
      state = SecureRandom.urlsafe_base64(32)
      url   = Emails::Adapters::GmailSession.auth_from_env
                                            .authorization_url(callback_uri: oauth_callback_settings_email_connectors_url, state:)
      session[:gmail_oauth] = { connector_id: @email_connector.id, state: }
      redirect_to url, allow_other_host: true
    rescue Emails::NotConfigured, Google::Auth::InitializationError, MultiJson::ParseError, JSON::ParserError, SystemCallError => e
      log_setup_failure(e)
      redirect_to edit_settings_email_connector_path(@email_connector),
                  alert: "Gmail is not configured on the server. Check the server logs."
    end

    def oauth_callback
      oauth     = session.delete(:gmail_oauth).to_h.with_indifferent_access
      rejection = oauth_rejection(oauth)
      return reject_oauth(*rejection) if rejection

      @email_connector = EmailConnector.find_by(id: oauth[:connector_id])
      return reject_oauth("Email connector no longer exists.", "connector #{oauth[:connector_id]} not found") unless @email_connector

      exchange_gmail_code
    rescue StandardError => e
      Rails.logger.error { "Gmail OAuth failed: #{e.class}: #{e.message}" }
      oauth_failed("Gmail authorization failed. Check the server logs.")
    end

    private

    # A parser message can quote the file, which holds the OAuth client secret, so log only its class.
    def log_setup_failure(error)
      detail = FILE_QUOTING_ERRORS.any? { |klass| error.is_a?(klass) } ? "" : ": #{error.message}"
      Rails.logger.error { "Gmail setup failed: #{error.class}#{detail}" }
    end

    def oauth_state_valid?(expected)
      expected.present? && ActiveSupport::SecurityUtils.secure_compare(params[:state].to_s, expected.to_s)
    end

    # Why the callback request must not proceed, as [alert, log reason], or nil.
    def oauth_rejection(oauth)
      return [ "OAuth session expired. Please try again.", oauth_state_problem(oauth[:state]) ] unless oauth_state_valid?(oauth[:state])

      [ "Gmail authorization was not granted.", "Google returned error=#{params[:error].to_s.truncate(64).inspect}" ] if params[:error].present?
    end

    def oauth_state_problem(expected)
      return "no OAuth state in session" if expected.blank?
      return "callback has no state" if params[:state].blank?

      "state mismatch"
    end

    def reject_oauth(message, reason)
      Rails.logger.warn { "Gmail OAuth callback rejected: #{reason}" }
      oauth_failed(message)
    end

    def exchange_gmail_code
      Emails::Adapters::GmailSession.auth_from_env
                                    .exchange_code(code: params[:code], callback_uri: oauth_callback_settings_email_connectors_url)
      redirect_to edit_settings_email_connector_path(@email_connector), notice: "Gmail connected successfully."
    end

    def oauth_failed(message)
      target = @email_connector ? edit_settings_email_connector_path(@email_connector) : settings_email_connectors_path
      redirect_to target, alert: message
    end

    def set_email_connector
      @email_connector = EmailConnector.find(params[:id])
    end

    def require_gmail_connector
      return if @email_connector.provider == Emails::GMAIL

      redirect_to edit_settings_email_connector_path(@email_connector), alert: "Only Gmail connectors are authorized with Google."
    end

    def email_connector_params
      params.expect(email_connector: [ :name, :provider, :enabled, configuration: [ :username, :password ] ])
    end
  end
end
