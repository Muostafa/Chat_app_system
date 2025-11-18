Rails.application.routes.draw do
  # Health check endpoint for Docker/Kubernetes/load balancers
  # Returns 200 if all services (MySQL, Redis, Elasticsearch) are healthy
  get '/health', to: 'health#index'

  # API routes - versioned and nested resources
  namespace :api do
    namespace :v1 do
      # Applications -> Chats -> Messages hierarchy
      resources :chat_applications, param: :token do
        resources :chats, param: :number do
          resources :messages, param: :number do
            collection do
              get :search  # Elasticsearch full-text search
            end
          end
        end
      end
    end
  end
end
