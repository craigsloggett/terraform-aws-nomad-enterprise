consul {
  address              = "127.0.0.1:8501"
  token                = "${consul_token}"
  ssl                  = true
  verify_ssl           = false
  auto_advertise       = true
  server_auto_join     = true
  server_service_name  = "nomad-server"
}
