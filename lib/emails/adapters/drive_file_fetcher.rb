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
      Entry = Data.define(:id, :name, :mime_type, :md5, :modified_time, :web_view_link)
      # +empty_folder_ids+: the requested folders under which no file was found at all (see #scan_folders).
      Scan = Data.define(:entries, :empty_folder_ids)

      FOLDER_MIME = "application/vnd.google-apps.folder".freeze
      GOOGLE_DOC_MIME = "application/vnd.google-apps.document".freeze
      DOCX_MIME = "application/vnd.openxmlformats-officedocument.wordprocessingml.document".freeze
      LIST_FIELDS = "nextPageToken,files(id,name,mimeType,md5Checksum,modifiedTime,webViewLink)".freeze

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
        name = meta.fetch("name") # steep:ignore
        mime_type = meta.fetch("mimeType") # steep:ignore
        return File.new(data: get(file_id, alt: "media"), filename: name, mime_type: mime_type) unless mime_type == GOOGLE_DOC_MIME

        File.new(data: export(file_id), filename: name, mime_type: DOCX_MIME)
      end

      # A Google Doc exported as docx (native Docs have no bytes of their own).
      def export(file_id)
        get(file_id, "export", mimeType: DOCX_MIME)
      end

      # Every non-folder file under the given folders, recursively; a file reachable twice is returned once.
      def scan(folder_ids)
        scan_folders(folder_ids).entries
      end

      # Like #scan, plus the folders that yielded no file. Drive answers a revoked, deleted or mistyped folder id
      # with an empty listing rather than an error, so the caller cannot tell it from a truly empty folder except by
      # being careful about what an empty folder implies. A file found under several folders counts for each of
      # them, so every folder is walked with its own visited set.
      def scan_folders(folder_ids)
        entries = {} # : Hash[String, Entry]
        empty = folder_ids.select { |folder_id| collect(folder_id, Set.new, entries).zero? }
        Scan.new(entries: entries.values, empty_folder_ids: empty)
      end

      private

      # Adds the files under +folder_id+ to +entries+; returns how many files it found (already known ones included).
      def collect(folder_id, seen, entries)
        return 0 unless seen.add?(folder_id)

        folders, files = list_children(folder_id).partition { |entry| entry.mime_type == FOLDER_MIME }
        files.each { |entry| entries[entry.id] ||= entry }
        folders.sum(files.size) { |folder| collect(folder.id, seen, entries) }
      end

      def list_children(folder_id)
        entries = [] # : Array[Entry]
        page_token = nil
        loop do
          page = JSON.parse(list_page(folder_id, page_token))
          entries.concat(Array(page["files"]).map { |attrs| entry(attrs) }) # steep:ignore
          page_token = page["nextPageToken"] # steep:ignore
          return entries unless page_token
        end
      end

      def list_page(folder_id, page_token)
        params = { q: "'#{folder_id}' in parents and trashed=false", fields: LIST_FIELDS, pageSize: 1000,
                   includeItemsFromAllDrives: true }
        params[:pageToken] = page_token if page_token
        get(nil, **params)
      end

      def entry(attrs)
        Entry.new(id: attrs.fetch("id").to_s, name: attrs.fetch("name").to_s, mime_type: attrs.fetch("mimeType").to_s,
                  md5: attrs["md5Checksum"], modified_time: attrs["modifiedTime"], web_view_link: attrs["webViewLink"])
      end

      def get(file_id, action = nil, **params)
        uri = URI([ BASE_URL, file_id && URI.encode_uri_component(file_id), action ].compact.join("/"))
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
