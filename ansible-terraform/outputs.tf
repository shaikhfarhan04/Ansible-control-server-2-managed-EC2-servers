output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "subnet_id" {
  description = "Public subnet ID"
  value       = aws_subnet.public.id
}

output "ansible_instance_id" {
  description = "Ansible server instance ID"
  value       = aws_instance.ansible.id
}

output "ansible_public_ip" {
  description = "Ansible server public IP"
  value       = aws_instance.ansible.public_ip
}

output "ansible_private_ip" {
  description = "Ansible server private IP"
  value       = aws_instance.ansible.private_ip
}

output "web_server_1_public_ip" {
  description = "Web server 1 public IP"
  value       = aws_instance.web[0].public_ip
}

output "web_server_1_private_ip" {
  description = "Web server 1 private IP"
  value       = aws_instance.web[0].private_ip
}

output "web_server_2_public_ip" {
  description = "Web server 2 public IP"
  value       = aws_instance.web[1].public_ip
}

output "web_server_2_private_ip" {
  description = "Web server 2 private IP"
  value       = aws_instance.web[1].private_ip
}

output "ssh_command" {
  description = "SSH command for Ansible server"
  value       = "ssh -i ansible-terraform.pem ec2-user@${aws_instance.ansible.public_ip}"
}

output "ansible_ping_command" {
  description = "Ansible ping command"
  value       = "ansible all -m ping"
}

output "ansible_playbook_command" {
  description = "Ansible webserver playbook command"
  value       = "ansible-playbook /etc/ansible/playbooks/webserver.yml"
}