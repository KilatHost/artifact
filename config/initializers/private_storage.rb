Rails.application.config.active_storage.draw_routes = false
Rails.application.config.filter_parameters += %i[password token access_token refresh_token code client_secret content file]
