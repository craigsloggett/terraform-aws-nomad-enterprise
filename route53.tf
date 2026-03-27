resource "aws_route53_record" "nomad" {
  zone_id = var.route53_zone.zone_id
  name    = local.nomad_fqdn
  type    = "A"

  alias {
    name                   = aws_lb.nomad.dns_name
    zone_id                = aws_lb.nomad.zone_id
    evaluate_target_health = true
  }
}
