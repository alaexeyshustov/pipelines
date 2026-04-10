Rails.application.config.to_prepare do
  Rails.application.config.view_component.preview_paths = [
    Rails.root.join("spec/components/previews").to_s
  ]
end
