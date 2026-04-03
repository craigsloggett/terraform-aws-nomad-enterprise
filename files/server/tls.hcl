tls {
  http = true
  rpc  = true

  ca_file   = "/etc/nomad.d/tls/nomad-ca.pem"
  cert_file = "/etc/nomad.d/tls/nomad-server.pem"
  key_file  = "/etc/nomad.d/tls/nomad-server-key.pem"

  verify_server_hostname = true
  verify_https_client    = false
}
