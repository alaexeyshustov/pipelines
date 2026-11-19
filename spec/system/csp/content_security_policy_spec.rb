require "rails_helper"

# Browser-level proof that the enforced CSP (GH #312) does not break the UI.
# Each flow fails on any securitypolicyviolation event, and on broken behaviour
# (inline handlers/scripts/styles that CSP would block).
RSpec.describe "Content Security Policy in the browser", :js do
  def yahoo_fields = "[data-provider-fields-target='fields']"

  before { watch_csp_violations }

  describe "email connector form" do
    it "toggles the Yahoo fields when the provider changes, after Turbo navigation", :aggregate_failures do
      visit settings_email_connectors_path
      click_link "New Connector"

      expect(page).to have_css("h1", text: "New Email Connector")
      expect(page).to have_no_css(yahoo_fields, visible: :visible)

      select "Yahoo", from: "Provider"
      expect(page).to have_css(yahoo_fields, visible: :visible)

      select "Gmail", from: "Provider"
      expect(page).to have_no_css(yahoo_fields, visible: :visible)
      expect_csp_enforced_without_violations
    end
  end

  describe "schema builder" do
    it "submits on field change and toggles Raw JSON on the agent form, reached by link click" do
      visit orchestration_agents_path
      click_link "New Agent"
      click_on "Schema Builder"

      within("#schema_builder") { select "object", from: "new_type" }
      expect(page).to have_css("#schema_builder", text: "Add property")

      click_button "Raw JSON"
      expect(page).to have_css("[data-schema-builder-target='rawView']", visible: :visible)
      expect(page).to have_css("[data-schema-builder-target='builderView']", visible: :hidden)
      expect_csp_enforced_without_violations
    end

    it "submits the description on blur and re-renders the frame with the value" do
      visit new_orchestration_pipeline_path
      click_on "Schema Builder"
      within("#schema_builder") { select "object", from: "new_type" }
      expect(page).to have_css("#schema_builder", text: "Add property")

      field = find("#schema_builder input[name='builder[description]']", match: :first)
      field.fill_in with: "Blur submitted description"
      field.send_keys :tab

      expect(page).to have_css("#schema_builder input[name='builder[description]'][value='Blur submitted description']")
      expect_csp_enforced_without_violations
    end

    it "toggles Raw JSON on the pipeline form" do
      visit new_orchestration_pipeline_path
      click_on "Schema Builder"

      click_button "Raw JSON"
      expect(page).to have_css("[data-schema-builder-target='rawView']", visible: :visible)
      expect_csp_enforced_without_violations
    end
  end

  describe "engine dashboards" do
    it "loads /jobs without violations" do
      visit "/jobs"
      expect(page).to have_css("body")
      expect_csp_enforced_without_violations
    end

    # ga.jspm.io is fetched from the network. Run only when explicitly enabled
    # (CSP_NETWORK_SPECS=1, set it in CI) so offline runs stay green.
    it "loads /monitoring with its importmap scripts", skip: (ENV["CSP_NETWORK_SPECS"] ? false : "needs network access to ga.jspm.io (set CSP_NETWORK_SPECS=1)") do
      visit "/monitoring"
      # Rendered by the chart controller loaded from the jspm importmap, so this
      # proves the engine's modules (and their nested imports) executed.
      expect(page).to have_css(".apexcharts-canvas", wait: 15)
      expect_csp_enforced_without_violations
    end
  end

  describe "Turbo navigation between the app and the engines" do
    network_skip = ENV["CSP_NETWORK_SPECS"] ? false : "needs network access to ga.jspm.io (set CSP_NETWORK_SPECS=1)"

    it "navigates app -> Jobs -> app without violations" do
      visit root_path
      open_sidebar_link "Settings", "Jobs"
      expect(page).to have_current_path("/jobs", ignore_query: true)
      expect_csp_enforced_without_violations

      # /jobs renders inside the app layout; its own "Back to main app" link is
      # invisible (dark on dark), so go back through the sidebar brand link.
      find("[data-testid='sidebar-brand']").click
      expect(page).to have_current_path("/", ignore_query: true)
      expect_csp_enforced_without_violations
    end

    it "navigates app -> Monitoring -> app without violations", skip: network_skip do
      visit root_path
      open_sidebar_link "LLM", "Monitoring"
      expect(page).to have_css(".apexcharts-canvas", wait: 15)
      expect_csp_enforced_without_violations

      back_to_app
      expect_csp_enforced_without_violations
    end

    def open_sidebar_link(group, label)
      within("[data-testid='sidebar']") do
        group_node = find("details", text: /#{group}/i, match: :first)
        group_node.find("summary").click unless group_node[:open]
        click_link label
      end
    end

    def back_to_app
      click_link "Back to main app"
      expect(page).to have_current_path("/", ignore_query: true)
      expect(page).to have_css("[data-testid='sidebar-brand']")
    end
  end
end
