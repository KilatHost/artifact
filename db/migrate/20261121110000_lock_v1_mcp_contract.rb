class LockV1McpContract < ActiveRecord::Migration[8.1]
  def change
    add_column :artifact_versions, :actor_type, :string
    add_column :artifact_versions, :actor_id, :bigint
    add_column :artifacts, :public_version_number, :integer
  end
end
