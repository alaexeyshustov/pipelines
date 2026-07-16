
require "rails_helper"

RSpec.describe UI::SidebarComponent, type: :component do
  subject(:rendered) { render_inline(component) }

  let(:component) { described_class.new(current_path: "/") }

  it "renders a nav element" do
    expect(rendered.css("[data-testid='sidebar']")).to be_present
  end

  it "renders the brand link" do
    brand = rendered.css("[data-testid='sidebar-brand']").first
    expect(brand.text.strip).to include("Application Pipeline")
    expect(brand["href"]).to eq("/")
  end

  it "renders four accordion groups" do
    summaries = rendered.css("details summary")
    labels = summaries.map { |s| s.text.strip }
    expect(labels).to eq(%w[LLM Mails Orchestration Settings])
  end

  it "renders LLM group links" do
    details = rendered.css("details").first
    links = details.css("a").map { |a| a.text.strip }
    expect(links).to include("Chats", "Models", "Monitoring", "Evaluation", "Prompts")
  end

  it "renders Mails group links" do
    details = rendered.css("details")[1]
    links = details.css("a").map { |a| a.text.strip }
    expect(links).to include("Application Emails", "Interviews")
  end

  it "renders Orchestration group links" do
    details = rendered.css("details")[2]
    links = details.css("a").map { |a| a.text.strip }
    expect(links).to include("Pipelines", "Actions", "Agents", "Pipeline Runs")
  end

  it "renders Settings group with Email Connectors link" do
    details = rendered.css("details")[3]
    links = details.css("a[data-testid='sidebar-item']").map { |a| a.text.strip }
    expect(links).to include("Email Connectors")
  end

  context "when current_path is in LLM group" do
    let(:component) { described_class.new(current_path: "/chats") }

    it "opens the LLM group" do
      llm_details = rendered.css("details").first
      expect(llm_details["open"]).not_to be_nil
    end

    it "does not open other groups" do
      other_details = rendered.css("details").to_a.drop(1)
      other_details.each do |d|
        expect(d["open"]).to be_nil
      end
    end
  end

  context "when current_path is in Mails group" do
    let(:component) { described_class.new(current_path: "/application_mails") }

    it "opens the Mails group" do
      mails_details = rendered.css("details")[1]
      expect(mails_details["open"]).not_to be_nil
    end
  end

  context "when current_path exactly matches a nav item" do
    let(:component) { described_class.new(current_path: "/chats") }

    it "highlights the active item" do
      chats_link = rendered.css("[data-testid='sidebar-item']").find { |a| a.text.strip == "Chats" }
      expect(chats_link["class"]).to include("font-medium")
    end

    it "does not highlight inactive items" do
      inactive = rendered.css("[data-testid='sidebar-item']").reject { |a| a.text.strip == "Chats" }
      inactive.each do |link|
        expect(link["class"]).not_to include("font-medium")
      end
    end
  end

  context "when current_path is nested under a nav item" do
    let(:component) { described_class.new(current_path: "/jobs/failed") }

    it "opens the Settings group" do
      settings_details = rendered.css("details")[3]
      expect(settings_details["open"]).not_to be_nil
    end

    it "highlights the parent Jobs item" do
      jobs_link = rendered.css("[data-testid='sidebar-item']").find { |a| a.text.strip == "Jobs" }
      expect(jobs_link["class"]).to include("font-medium")
    end
  end
end
