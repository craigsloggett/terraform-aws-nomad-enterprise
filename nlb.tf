resource "aws_lb" "nomad" {
  name_prefix        = "nomad-"
  internal           = var.nlb_internal
  load_balancer_type = "network"
  subnets            = var.nlb_internal ? local.vpc.private_subnet_ids : local.vpc.public_subnet_ids

  tags = merge(var.common_tags, { Name = "${var.project_name}-nomad" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group" "nomad" {
  name_prefix = "nomad-"
  port        = 4646
  protocol    = "TLS"
  vpc_id      = local.vpc.id

  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = "4646"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = merge(var.common_tags, { Name = "${var.project_name}-nomad" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "nomad" {
  load_balancer_arn = aws_lb.nomad.arn
  port              = 4646
  protocol          = "TLS"
  certificate_arn   = aws_acm_certificate_validation.nomad.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nomad.arn
  }
}

resource "aws_lb_target_group_attachment" "nomad" {
  count = local.nomad_server_count

  target_group_arn = aws_lb_target_group.nomad.arn
  target_id        = aws_instance.nomad_server[count.index].id
  port             = 4646
}
