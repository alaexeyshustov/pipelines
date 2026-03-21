class ManageTempFileTool < RubyLLM::Tool
  description "Read and write temporary files in the /tmp directory. " \
              "Supports actions: 'read' (read file content), 'write' (write content to file), 'delete' (delete a file)."

  param :action,   type: :string, desc: "Action: read, write, or delete", required: true
  param :filename, type: :string, desc: "Filename (without path) to
      read from or write to in the /tmp directory. Example: 'output.txt'", required: true
  param :content,  type: :string, desc: "Content to write to the file (required for write action)", required: false

  def execute(action:, filename:, content: nil)
    path = Rails.root.join("tmp", filename)

    case action
    when "read"
      if File.exist?(path)
        File.read(path)
      else
        "File not found: #{filename}"
      end
    when "write"
      if content.nil? || content.strip.empty?
        "Content is required for write action"
      else
        # Ensure the /tmp directory exists
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
