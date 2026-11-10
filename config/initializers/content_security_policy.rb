# App-wide policy for signed-in pages. Artifact previews and public snapshots
# send their own stricter sandbox policy, which takes precedence.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src  :self
    policy.style_src   :self, :unsafe_inline
    policy.img_src     :self, :data
    policy.font_src    :self
    policy.connect_src :self
    policy.frame_src   :self
    policy.object_src  :none
    policy.base_uri    :self
    policy.frame_ancestors :none
  end

  # The import map is an inline script; it carries this nonce. The session id
  # keeps it stable across Turbo visits within one session.
  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  config.content_security_policy_nonce_directives = %w[script-src]
end
