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
    end
  end
  resources :design_kits, only: %i[index create update]
  resources :connections, only: %i[index create destroy]
  get "p/:public_id", to: "public_artifacts#show", as: :public_artifact
end
