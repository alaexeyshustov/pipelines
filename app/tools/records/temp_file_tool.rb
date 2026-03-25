module Records
  class TempFileTool < RubyLLM::Tool
    description "Read and write temporary files in the /tmp directory. " \
                "Supports actions: 'read' (read file content), 'write' (write content to file), 'delete' (delete a file)."

    param :action,   type: :string, desc: "Action: read, write, or delete", required: true
    param :filename, type: :string, desc: "Filename (without path) to
        read from or write to in the /tmp directory. Example: 'output.txt'", required: true
    param :content,  type: :string, desc: "Content to write to the file (required for write action)", required: false

    def name = "temp_file"

    def execute(action:, filename:, content: nil)
      path = Rails.root.join("tmp", filename)

      case action
      when "read"
        File.exist?(path) ? File.read(path) : "File not found: #{filename}"
      when "write"
        if content.nil? || content.strip.empty?
          "Content is required for write action"
        else
          FileUtils.mkdir_p(Rails.root.join("tmp"))
          File.write(path, content)
          "File written successfully: #{filename}"
        end
      when "delete"
        if File.exist?(path)
          File.delete(path)
          "File deleted successfully: #{filename}"
        else
          "File not found, cannot delete: #{filename}"
        end
      else
        "Unknown action '#{action}'. Use: read, write, or delete."
      end
    end
  end
end
