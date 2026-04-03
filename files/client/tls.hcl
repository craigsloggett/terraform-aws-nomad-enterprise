tls {
  http = true
  rpc  = true

  ca_file   = "/etc/nomad.d/tls/nomad-ca.pem"
  cert_file = "/etc/nomad.d/tls/nomad-client.pem"
  key_file  = "/etc/nomad.d/tls/nomad-client-key.pem"

  verify_server_hostname = true
  verify_https_client    = false
}
