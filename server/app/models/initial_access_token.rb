class InitialAccessToken < Token
  def return_to
    redirect_uri
  end

  def issue!
    client.issue_credentials!
    client
  end
end
