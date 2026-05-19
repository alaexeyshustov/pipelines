RSpec.shared_examples "a searchable and paginable index" do
  # Requires:
  #   let(:resource_path) - evaluated path string for the index action
  #   let(:record_factory) - symbol factory name (e.g., :interview)

  it "renders pagination controls when records exceed page size" do
    create_list(record_factory, 21)
    get resource_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('aria-label="Pages"')
  end

  it "ignores invalid per_page and uses default" do
    get resource_path, params: { per_page: 999 }
    expect(response).to have_http_status(:ok)
  end

  it "filters results by company name" do
    create(record_factory, company: "Acme Corp",  job_title: "Backend")
    create(record_factory, company: "Other Corp", job_title: "Frontend")
    get resource_path, params: { q: "Acme" }
    expect(response.body).to     include("Acme Corp")
    expect(response.body).not_to include("Other Corp")
  end

  it "filters results by job title" do
    create(record_factory, company: "Acme", job_title: "Backend Engineer")
    create(record_factory, company: "Beta", job_title: "Product Manager")
    get resource_path, params: { q: "Engineer" }
    expect(response.body).to     include("Backend Engineer")
    expect(response.body).not_to include("Product Manager")
  end

  it "shows all records when query is blank" do
    create(record_factory, company: "Acme", job_title: "Backend")
    create(record_factory, company: "Beta", job_title: "Frontend")
    get resource_path, params: { q: "" }
    expect(response.body).to include("Acme")
    expect(response.body).to include("Beta")
  end
end
