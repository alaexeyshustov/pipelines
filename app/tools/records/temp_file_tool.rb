module Records
  class TempFileTool < RubyLLM::Tool
    def self.readonly? = false

    description "Read and write temporary files in the /tmp directory. " \
                "Supports actions: 'read' (read file content), 'write' (write content to file), 'delete' (delete a file)."

    param :action,   type: :string, desc: "Action: read, write, or delete", required: true
    param :filename, type: :string, desc: "Filename (without path) to
        read from or write to in the /tmp directory. Example: 'output.txt'", required: true
    param :content,  type: :string, desc: "Content to write to the file (required for write action)", required: false

    def name = "temp_file"

    def execute(action:, filename:, content: nil)
      root = Rails.root # : Pathname
      path = root.join("tmp", filename)

      case action
      when "read"   then read_file(path, filename)
      when "write"  then write_file(root, path, filename, content)
      when "delete" then delete_file(path, filename)
      else "Unknown action '#{action}'. Use: read, write, or delete."
      end
    end

    private

    def read_file(path, filename)
      File.exist?(path) ? File.read(path.to_s) : "File not found: #{filename}"
    end

    def write_file(root, path, filename, content)
      if content.nil? || content.strip.empty?
        "Content is required for write action"
      else
        FileUtils.mkdir_p(root.join("tmp"))
        File.write(path.to_s, content)
        "File written successfully: #{filename}"
      end
    end

    def delete_file(path, filename)
      if File.exist?(path)
        File.delete(path)
        "File deleted successfully: #{filename}"
      else
        "File not found, cannot delete: #{filename}"
      end
    end
  end
end
