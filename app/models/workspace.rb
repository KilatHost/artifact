class Workspace < ApplicationRecord
  belongs_to :user
  has_many :artifacts, dependent: :restrict_with_error
  has_many :design_kits, dependent: :restrict_with_error
  has_many :api_tokens, dependent: :destroy
  validates :name, presence: true, length: { maximum: 120 }
end
