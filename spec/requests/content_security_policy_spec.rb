require "rails_helper"

RSpec.describe "Content Security Policy" do
  def csp
    header = response.headers["Content-Security-Policy"]
    expect(header).to be_present, "expected a Content-Security-Policy header"
    header
  end

  def directive(name)
    csp.split(";").map(&:strip).find { |d| d.start_with?("#{name} ") }
  end

  def nonce
    directive("script-src")[/'nonce-([^']+)'/, 1]
  end

  describe "GET /" do
    before { get root_path }

    it "enforces (does not merely report) the policy" do
      expect(csp).to be_present
      expect(response.headers).not_to have_key("Content-Security-Policy-Report-Only")
    end

    it "limits scripts to self plus a per-request nonce" do
      expect(directive("script-src")).to match(/\Ascript-src 'self' 'nonce-[^']+'\z/)
    end

    it "sets the base directives", :aggregate_failures do
      expect(directive("default-src")).to eq("default-src 'self'")
      expect(directive("object-src")).to eq("object-src 'none'")
      expect(directive("base-uri")).to eq("base-uri 'self'")
      expect(directive("img-src")).to eq("img-src 'self' data:")
      expect(directive("font-src")).to eq("font-src 'self' data:")
      expect(directive("connect-src")).to eq("connect-src 'self'")
      expect(directive("frame-ancestors")).to eq("frame-ancestors 'none'")
      expect(directive("style-src")).to eq("style-src 'self' 'unsafe-inline'")
    end

    it "has no form-action directive (Gmail connect redirects to Google)" do
      expect(csp).not_to include("form-action")
    end

    it "does not allow ga.jspm.io" do
      expect(csp).not_to include("ga.jspm.io")
    end

    it "does not add a nonce to style-src" do
      expect(directive("style-src")).not_to include("nonce")
    end

    it "exposes the nonce through csp_meta_tag" do
      expect(response.body).to include(%(<meta name="csp-nonce" content="#{nonce}"))
    end
  end

  it "uses a different nonce on each request" do
    get root_path
    first = nonce
    get root_path

    expect(first).to be_present
    expect(nonce).not_to eq(first)
  end

  it "is sent on the /jobs dashboard without ga.jspm.io" do
    get "/jobs"

    expect(directive("script-src")).to match(/'nonce-[^']+'/)
    expect(csp).not_to include("ga.jspm.io")
  end

  it "allows ga.jspm.io in script-src only on /monitoring", :aggregate_failures do
    get "/monitoring"

    expect(response).to have_http_status(:ok)
    expect(directive("script-src")).to include("https://ga.jspm.io")
    expect(directive("script-src")).to match(/'nonce-[^']+'/)
    expect(directive("default-src")).to eq("default-src 'self'")
  end

  it "does not leak the monitoring override into later requests" do
    get "/monitoring"
    get "/"

    expect(request.path).to eq("/")
    expect(csp).not_to include("ga.jspm.io")
  end

  describe "connector form markup" do
    it "renders without inline scripts and wires the provider-fields controller", :aggregate_failures do
      get new_settings_email_connector_path
      doc = Nokogiri::HTML(response.body)

      expect(doc.css("script:not([src])").reject { |s| s["type"] == "importmap" }).to be_empty
      root = doc.at_css("[data-controller~='provider-fields']")
      expect(root).to be_present
      expect(root["data-provider-fields-provider-value"]).to eq(Emails::YAHOO)
      expect(root.at_css("select[data-provider-fields-target='select']")).to be_present
      expect(root.at_css("[data-provider-fields-target='fields']")).to be_present
    end
  end

  describe "hidden raw view" do
    %w[new_orchestration_agent_path new_orchestration_pipeline_path].each do |helper|
      it "uses the hidden class, not an inline style, on #{helper}" do
        get public_send(helper)
        raw = Nokogiri::HTML(response.body).at_css("[data-schema-builder-target='rawView']")

        expect(raw["class"].to_s.split).to include("hidden")
        expect(raw["style"]).to be_nil
      end
    end
  end

  describe "primitive_preview layout" do
    it "includes csp_meta_tag" do
      # Component previews are not routed in test, so render with the policy and
      # nonce generator a real request would carry in its env.
      config = Rails.application.config
      renderer = ApplicationController.renderer.new(
        "action_dispatch.content_security_policy" => config.content_security_policy,
        "action_dispatch.content_security_policy_nonce_generator" => config.content_security_policy_nonce_generator,
        "action_dispatch.content_security_policy_nonce_directives" => config.content_security_policy_nonce_directives
      )
      html = renderer.render(inline: "x", layout: "primitive_preview")

      expect(Nokogiri::HTML(html).at_css("meta[name='csp-nonce']")).to be_present
    end
  end
end
