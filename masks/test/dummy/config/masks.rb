Masks.configure do
  policy :login do
    
  end

  # This should be moved to Masks::MasksPolicy
  policy :masks do
    device captcha: :turnstile

    # sso on: '/sso'
    # oidc on: '/oidc'
    # login on: '/login'
    # admin on: '/masks'
    # gql on: '/masks.graphql'
  end

  policy inherits: :masks do
    # logged_in on: '/dashboard'
    # logged_in optional: true
  end
end
