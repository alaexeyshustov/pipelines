# Enforced content security policy. See docs/adr/0016-content-security-policy.md.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src     :self
    policy.object_src      :none
    policy.base_uri        :self
    policy.img_src         :self, :data
    policy.font_src        :self, :data
    policy.connect_src     :self
    policy.frame_ancestors :none
    policy.script_src      :self
    # Turbo, tom-select and the chart libraries inject inline styles.
    policy.style_src       :self, :unsafe_inline
  end

  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
end
