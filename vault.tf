resource "vault_mount" "nomad" {
  path        = "kv/nomad"
  type        = "kv-v2"
  description = "Infrastructure bootstrap secrets for Nomad"
}
