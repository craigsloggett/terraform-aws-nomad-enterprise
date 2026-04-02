consul {
  address             = "127.0.0.1:8501"
  grpc_address        = "127.0.0.1:8503"
  token               = "${consul_token}"
  ssl                 = true
  verify_ssl          = false
  auto_advertise      = true
  client_auto_join    = true
  server_service_name = "nomad-server"
  client_service_name = "nomad-client"
}
