class CreateDoorkeeperTables < ActiveRecord::Migration[8.1]
  def change
    create_table :oauth_applications do |t|
      t.string :name, null: false
      t.string :uid, null: false
      t.string :secret
      t.text :redirect_uri, null: false
      t.string :scopes, null: false, default: ""
      t.boolean :confidential, null: false, default: true
      t.timestamps null: false
    end
    add_index :oauth_applications, :uid, unique: true
    create_table :oauth_access_grants do |t|
      t.references :resource_owner, null: false, foreign_key: { to_table: :users }
      t.references :application, null: false, foreign_key: { to_table: :oauth_applications }
      t.string :token, null: false
      t.integer :expires_in, null: false
      t.text :redirect_uri, null: false
      t.string :scopes, null: false, default: ""
      t.datetime :created_at, null: false
      t.datetime :revoked_at
      t.string :code_challenge
      t.string :code_challenge_method
    end
    add_index :oauth_access_grants, :token, unique: true
    create_table :oauth_access_tokens do |t|
      t.references :resource_owner, foreign_key: { to_table: :users }
      t.references :application, null: false, foreign_key: { to_table: :oauth_applications }
      t.string :token, null: false
      t.string :refresh_token
      t.integer :expires_in
      t.string :scopes
      t.datetime :created_at, null: false
      t.datetime :revoked_at
    end
    add_index :oauth_access_tokens, :token, unique: true
    add_index :oauth_access_tokens, :refresh_token, unique: true
  end
end
