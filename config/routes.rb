Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  draw :auth
  root "artifacts#index"
  resources :artifacts, only: %i[index new create show update] do
    member do
      get :preview
      get :export
      post :publish
      post :unpublish
      post :restore
      post :upload
      post :archive
      post :unarchive
    end
  end
  resources :design_kits, only: %i[index create update]
  resources :connections, only: %i[index create destroy]
  get "p/:public_id", to: "public_artifacts#show", as: :public_artifact
  get "p/:public_id/frame", to: "public_artifacts#frame", as: :public_artifact_frame
  get "p/:public_id/file", to: "public_artifacts#file", as: :public_artifact_file
end
