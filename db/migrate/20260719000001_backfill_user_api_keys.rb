class BackfillUserApiKeys < ActiveRecord::Migration[8.1]
  # Give every existing user an API key. New users get one automatically via a
  # before_create callback; this covers rows created before the column existed.
  # Idempotent: only fills rows where api_key is still NULL.
  def up
    User.where(api_key: nil).find_each do |user|
      user.update_columns(api_key: User.new_api_key)
    end
  end

  def down
    # No-op: keys are credentials, not derived data — don't destroy them.
  end
end
