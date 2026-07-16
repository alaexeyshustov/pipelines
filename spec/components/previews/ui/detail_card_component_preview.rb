
module UI
  class DetailCardComponentPreview < ViewComponent::Preview
    Record = Data.define(:name, :status, :created_at)

    def default
      record = Record.new(name: "Acme Corp Application", status: "active", created_at: Time.current)
      render(UI::DetailCardComponent.new(
        entity: record,
        attributes: [
          { label: "Name",       attribute: :name,       type: :text },
          { label: "Status",     attribute: :status,     type: :text },
          { label: "Created At", attribute: :created_at, type: :date }
        ]
      ))
    end
  end
end
