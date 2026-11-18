module Records
  class TempFileTool < RubyLLM::Tool
    FILENAME_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9._-]{0,63}\z/
    MAX_WRITE_BYTES  = 100.kilobytes
    WRITE_FLAGS      = File::WRONLY | File::CREAT | File::TRUNC | File::NOFOLLOW

    def self.readonly? = false

    def self.scratch_dir
      @scratch_dir || Rails.root.join("tmp/agent_scratch")
    end

    def self.scratch_dir=(dir)
      @scratch_dir = dir
    end

    description "Read and write temporary scratch files. " \
                "Supports actions: 'read' (read file content), 'write' (write content to file), 'delete' (delete a file)."

    parameter :action,   type: :string, description: "Action: read, write, or delete", required: true
    parameter :filename, type: :string, description: "Plain filename (no path, up to 64 characters of letters, digits, '.', '_' or '-', " \
                                                      "starting with a letter or digit) of the scratch file. Example: 'output.txt'", required: true
    parameter :content,  type: :string, description: "Content to write to the file (required for write action, up to 100 KB)", required: false

    def name = "temp_file"

    def execute(action:, filename:, content: nil)
      return "Unknown action '#{action}'. Use: read, write, or delete." unless %w[read write delete].include?(action)
      return "Invalid filename: #{filename.inspect}" unless valid_filename?(filename)

      path = self.class.scratch_dir.join(filename)

      case action
      when "read"  then read_file(path, filename)
      when "write" then write_file(path, filename, content)
      else delete_file(path, filename)
      end
    end

    private

    def valid_filename?(filename)
      filename.is_a?(String) && FILENAME_PATTERN.match?(filename)
    end

    def read_file(path, filename)
      File.open(path.to_s, File::RDONLY | File::NOFOLLOW) { |file| file.read.to_s }
    rescue Errno::ENOENT
      "File not found: #{filename}"
    rescue SystemCallError => error
      "Cannot read #{filename}: #{error.class.name.demodulize}"
    end

    def write_file(path, filename, content)
      return "Content is required for write action" if content.nil? || content.strip.empty?
      return "Content too large: limit is 100 KB" if content.bytesize > MAX_WRITE_BYTES

      FileUtils.mkdir_p(self.class.scratch_dir)
      File.open(path.to_s, WRITE_FLAGS, 0o600) { |file| file.write(content) }
      "File written successfully: #{filename}"
    rescue SystemCallError => error
      "Cannot write #{filename}: #{error.class.name.demodulize}"
    end

    def delete_file(path, filename)
      if File.exist?(path) || File.symlink?(path)
        File.delete(path)
        "File deleted successfully: #{filename}"
      else
        "File not found, cannot delete: #{filename}"
      end
    rescue SystemCallError => error
      "Cannot delete #{filename}: #{error.class.name.demodulize}"
    end
  end
end
