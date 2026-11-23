# Records browser-side Content Security Policy violations in Cuprite (:js) specs.
# The listener is installed before any page script runs, so it also covers Turbo
# navigations (same document) and every full page load.
module CspViolations
  LISTENER = <<~JS.freeze
    window.__cspViolations = window.__cspViolations || [];
    document.addEventListener("securitypolicyviolation", function (e) {
      window.__cspViolations.push(e.violatedDirective + " blocked " + (e.blockedURI || "inline") + " @ " + e.sourceFile + ":" + e.lineNumber);
    });
  JS

  def watch_csp_violations
    page.driver.browser.evaluate_on_new_document(LISTENER)
  end

  def csp_violations
    page.evaluate_script("window.__cspViolations || []")
  end

  # Proves the page really ran under an enforced policy (so a green run is not
  # just "no CSP at all"), then that nothing was blocked.
  def expect_csp_enforced_without_violations
    header = page.evaluate_async_script(<<~JS)
      var done = arguments[arguments.length - 1];
      fetch(location.href).then(function (r) { done(r.headers.get("content-security-policy") || ""); });
    JS
    expect(header).to include("script-src"), "page was not served with a Content-Security-Policy"
    expect(csp_violations).to eq([])
  end
end

RSpec.configure do |config|
  config.include CspViolations, type: :system
end
