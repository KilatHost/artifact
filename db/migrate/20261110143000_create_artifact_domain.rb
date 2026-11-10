class CreateArtifactDomain < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.string :password_digest, null: false
      t.timestamps
    end
    add_index :users, :email, unique: true
    create_table :workspaces do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :name, null: false
      t.timestamps
    end
    create_table :design_kits do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string :name, null: false
      t.jsonb :tokens, null: false, default: {}
      t.integer :version, null: false, default: 1
      t.timestamps
    end
    create_table :artifacts do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :design_kit, foreign_key: true
      t.string :title, null: false
      t.string :kind, null: false
      t.bigint :current_version_id
      t.bigint :published_version_id
      t.string :public_id, null: false
      t.timestamps
    end
    add_index :artifacts, :public_id, unique: true
    create_table :artifact_versions do |t|
      t.references :artifact, null: false, foreign_key: true
      t.integer :number, null: false
      t.string :title, null: false
      t.string :kind, null: false
      t.text :content, null: false, default: ""
      t.jsonb :design_tokens, null: false, default: {}
      t.string :author, null: false
      t.timestamps
    end
    add_index :artifact_versions, [ :artifact_id, :number ], unique: true
    add_foreign_key :artifacts, :artifact_versions, column: :current_version_id
    add_foreign_key :artifacts, :artifact_versions, column: :published_version_id
    create_table :api_tokens do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string :name, null: false
      t.string :token_digest, null: false
      t.string :scopes, null: false
      t.timestamps
    end
    add_index :api_tokens, :token_digest, unique: true
  end
end
