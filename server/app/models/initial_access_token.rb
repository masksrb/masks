class InitialAccessToken < Token
  def return_to
    redirect_uri
  end

  def redeem!
    consume!
    client.issue_credentials!
    client
  end
end
