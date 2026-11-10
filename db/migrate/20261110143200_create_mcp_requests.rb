class CreateMcpRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :mcp_requests do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string :request_id, null: false, limit: 128
      t.string :fingerprint, null: false
      t.jsonb :result, null: false
      t.timestamps
    end
    add_index :mcp_requests, [ :workspace_id, :request_id ], unique: true
  end
end
