
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  :rid, :code, :backup_code, :code_verifier, :code_challenge, :state, :nonce
]
