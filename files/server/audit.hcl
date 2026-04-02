audit {
  enabled = true

  sink "file" {
    type               = "file"
    delivery_guarantee = "enforced"
    format             = "json"
    path               = "/opt/nomad/data/audit/audit.log"
    rotate_bytes       = 104857600
    rotate_duration    = "24h"
    rotate_max_files   = 14
  }
}
