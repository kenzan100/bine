class User < ActiveRecord::Base
  has_many :messages

  def update_token!(object)
    if object.refresh_token
      self.refresh_token = object.refresh_token
    end

    self.update_attributes(
      :access_token  => object.access_token,
      :expires_in    => object.expires_in,
      :issued_at     => object.issued_at,
    )
  end

  def token_hash
    return {
      :refresh_token => self.refresh_token,
      :access_token  => self.access_token,
      :expires_in    => self.expires_in,
      :issued_at     => Time.at(self.issued_at)
    }
  end
end
