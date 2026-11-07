data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_key_pair" "admin" {
  key_name   = "swiggy-admin"
  public_key = var.ssh_public_key
}

resource "aws_instance" "server" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.server.id]
  key_name                    = aws_key_pair.admin.key_name
  associate_public_ip_address = true #trivy:ignore:AVD-AWS-0164 The server is reached directly; there is no load balancer.

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    encrypted             = true
    delete_on_termination = true
  }

  # A new AMI should not replace a running server.
  lifecycle {
    ignore_changes = [ami]
  }

  tags = {
    Name = "swiggy-k3s-server"
  }
}
