# ADR 0016: Content Security Policy

## Status
Accepted (GH #312, part of #240 SEC-13)

## Context

The initializer was fully commented out, so nothing limited where scripts could come from. The app had two sources of inline JS (the email connector form and `Orchestration::SchemaBuilderComponent`) and two `style="display:none"` attributes. The Pagy `series_nav` override also put `page_url(...)` into `href` unescaped.

## Decision

- **Enforced everywhere.** The policy is enforced (not report-only) in every environment, including test, so specs catch regressions. `default-src 'self'`, `object-src 'none'`, `base-uri 'self'`, `frame-ancestors 'none'`, `img-src` and `font-src` `'self' data:`, `connect-src 'self'`.
- **Script nonce only.** `script-src 'self'` plus a fresh `SecureRandom.base64(16)` nonce per request (`nonce_directives = %w[script-src]`). The nonce is not derived from the session id.
- **Styles keep `'unsafe-inline'` for now.** Turbo (progress bar), tom-select and the chart libraries (ApexCharts, chart.js) inject inline styles. Follow-up: drop `unsafe-inline` once those are nonced or replaced.
- **Per-engine exception for `/monitoring`.** The RubyLLM Monitoring engine pins scripts from `https://ga.jspm.io`. Its `ApplicationController` gets its own `script_src :self, "https://ga.jspm.io"` (in `config/initializers/ruby_llm_monitoring.rb`). The host is never added globally. `/jobs` needs nothing extra: importmap-rails applies the nonce to the inline importmap.
- **No `form-action`.** The Gmail connect POST redirects to Google; browsers apply `form-action` to redirect targets, so the directive would break it.
- **No inline `<script>` in bodies, turbo-frame or turbo-stream responses.** The nonce changes on every request and Turbo Drive keeps the first page's nonce, so such scripts would be blocked. Use a Stimulus controller (`provider-fields`, `auto-submit`) and `hidden` instead of `style=` or `on*=`. `.herb.yml` enforces it (`html-require-script-nonce`, `html-no-event-handler-attributes`, `html-no-inline-script-elements`).
- **Pagy.** `page_url(...)` in the `series_nav` override is wrapped in `ERB::Util.h`.

## Consequences

- A new inline script or handler fails `pnpm herb:lint` and the CSP specs.
- `spec/system/csp/` fails on console CSP violations; the `/monitoring` check needs the network and runs with `CSP_NETWORK_SPECS=1` (set in the CI e2e job).
- Inline styles remain a gap until `unsafe-inline` is dropped.
