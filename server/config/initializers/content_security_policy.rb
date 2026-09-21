Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.base_uri :none
    policy.object_src :none
    policy.frame_ancestors :none
    policy.script_src :self
    policy.style_src :self, :unsafe_inline
    policy.img_src :self, :data
    policy.font_src :self, :data
    policy.connect_src(*([ :self ] + (Rails.env.development? ? %i[ws wss http] : [])))
  end
end
