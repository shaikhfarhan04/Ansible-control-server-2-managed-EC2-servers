resource "tls_private_key" "ansible" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "ansible" {
  key_name   = "${var.project_name}-key"
  public_key = tls_private_key.ansible.public_key_openssh

  tags = {
    Name = "${var.project_name}-key"
  }
}

resource "local_sensitive_file" "private_key" {
  filename        = "${path.module}/ansible-terraform.pem"
  content         = tls_private_key.ansible.private_key_pem
  file_permission = "0400"
}