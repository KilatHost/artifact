class AddArchivedAtToArtifacts < ActiveRecord::Migration[8.1]
  def change
    add_column :artifacts, :archived_at, :datetime
    add_index :artifacts, :archived_at, where: "archived_at IS NOT NULL"
  end
end
