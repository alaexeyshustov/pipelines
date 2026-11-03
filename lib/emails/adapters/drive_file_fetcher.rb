require "net/http"
require "json"

module Emails
  module Adapters
    # Minimal Drive v3 client (files.get metadata + alt=media) over Net::HTTP. The google-apis Drive gem is
    # not bundled; the OAuth token comes from the shared googleauth flow (Emails::GmailAuth) with the
    # drive.readonly scope.
    class DriveFileFetcher
      class Error < StandardError; end
      class NotConfigured < Error; end

      File = Data.define(:data, :filename, :mime_type)

      SCOPE = [ "https://www.googleapis.com/auth/drive.readonly" ].freeze
      BASE_URL = "https://www.googleapis.com/drive/v3/files".freeze

      def self.from_env
        credentials_path = ENV.fetch("GMAIL_CREDENTIALS_PATH", Rails.root.join("credentials.json").to_s)
        token_path       = ENV.fetch("DRIVE_TOKEN_PATH", Rails.root.join("drive_token.yaml").to_s)
        unless ::File.exist?(credentials_path) && ::File.exist?(token_path)
          raise NotConfigured, "Google Drive is not configured: authorize drive.readonly " \
                               "(expected #{credentials_path} and #{token_path})"
        end

        new(access_token: token_provider(GmailAuth.new(credentials_path:, token_path:, scope: SCOPE)))
      end

      def self.token_provider(auth)
        lambda {
          creds = auth.credentials # steep:ignore
          creds.fetch_access_token! if creds.expired? # steep:ignore
          creds.access_token # steep:ignore
        }
      end

      def initialize(access_token:)
        @access_token = access_token
      end

      def fetch(file_id)
        meta = JSON.parse(get(file_id, fields: "name,mimeType"))
        File.new(data: get(file_id, alt: "media"), filename: meta.fetch("name"), mime_type: meta.fetch("mimeType")) # steep:ignore
      end

      private

      def get(file_id, **params)
        uri = URI("#{BASE_URL}/#{URI.encode_uri_component(file_id)}")
        uri.query = URI.encode_www_form(params.merge(supportsAllDrives: true))
        response = request(uri)
        raise Error, "Drive request failed (#{response.code})" unless response.is_a?(Net::HTTPSuccess)

        response.body.to_s
      end

      def request(uri)
        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{@access_token.call}"
        Net::HTTP.start(uri.host.to_s, uri.port, use_ssl: true) { |http| http.request(request) }
      end
    end
  end
end
