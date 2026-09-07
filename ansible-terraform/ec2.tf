data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}


resource "aws_instance" "web" {
  count = 2

  ami           = data.aws_ssm_parameter.al2023_ami.value
  instance_type = var.web_instance_type

  subnet_id = aws_subnet.public.id

  vpc_security_group_ids = [
    aws_security_group.web.id
  ]

  key_name = aws_key_pair.ansible.key_name

  associate_public_ip_address = true

  root_block_device {
    volume_size = 10
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = <<-EOF
    #!/bin/bash

    dnf update -y

    dnf install -y python3

    systemctl enable sshd
    systemctl start sshd
  EOF

  tags = {
    Name = "${var.project_name}-web-${count.index + 1}"
    Role = "webserver"
  }
}


resource "aws_instance" "ansible" {
  ami           = data.aws_ssm_parameter.al2023_ami.value
  instance_type = var.ansible_instance_type

  subnet_id = aws_subnet.public.id

  vpc_security_group_ids = [
    aws_security_group.ansible.id
  ]

  key_name = aws_key_pair.ansible.key_name

  associate_public_ip_address = true

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = <<-EOF
    #!/bin/bash

    set -e

    # Update operating system
    dnf update -y

    # Install required packages
    dnf install -y python3 python3-pip python3-devel gcc git tree openssh-clients

    # Create Ansible virtual environment
    python3 -m venv /opt/ansible-venv

    # Upgrade pip
    /opt/ansible-venv/bin/pip install --upgrade pip

    # Install Ansible
    /opt/ansible-venv/bin/pip install ansible

    # Make Ansible commands globally available
    ln -sf /opt/ansible-venv/bin/ansible /usr/local/bin/ansible
    ln -sf /opt/ansible-venv/bin/ansible-playbook /usr/local/bin/ansible-playbook
    ln -sf /opt/ansible-venv/bin/ansible-inventory /usr/local/bin/ansible-inventory

    # Create Ansible directories
    mkdir -p /etc/ansible/inventory
    mkdir -p /etc/ansible/playbooks
    mkdir -p /etc/ansible/aws

    # Install private key used by Ansible
    cat > /etc/ansible/aws/ansible.pem <<'KEY'
${tls_private_key.ansible.private_key_pem}
KEY

    chmod 400 /etc/ansible/aws/ansible.pem

    # Create inventory
    cat > /etc/ansible/inventory/hosts <<'INVENTORY'
[webservers]
web1 ansible_host=${aws_instance.web[0].private_ip}
web2 ansible_host=${aws_instance.web[1].private_ip}
INVENTORY

    # Create ansible.cfg
    cat > /etc/ansible/ansible.cfg <<'CONFIG'
[defaults]
inventory = /etc/ansible/inventory/hosts
remote_user = ec2-user
private_key_file = /etc/ansible/aws/ansible.pem
host_key_checking = False
retry_files_enabled = False
interpreter_python = auto_silent

[privilege_escalation]
become = true
become_method = sudo
become_user = root
become_ask_pass = false
CONFIG

    # Create ping playbook
    cat > /etc/ansible/playbooks/ping.yml <<'PLAYBOOK'
---
- name: Test Ansible connectivity
  hosts: webservers
  become: true

  tasks:
    - name: Ping managed servers
      ansible.builtin.ping:
PLAYBOOK

    # Create web server playbook
    cat > /etc/ansible/playbooks/webserver.yml <<'PLAYBOOK'
---
- name: Configure Apache web servers
  hosts: webservers
  become: true

  tasks:

    - name: Install Apache
      ansible.builtin.dnf:
        name: httpd
        state: present

    - name: Start and enable Apache
      ansible.builtin.service:
        name: httpd
        state: started
        enabled: true

    - name: Create index page
      ansible.builtin.copy:
        dest: /var/www/html/index.html
        mode: "0644"
        content: |
          <!DOCTYPE html>
          <html>
          <head>
              <title>Ansible Web Server</title>
          </head>
          <body>
              <h1>Hello from {{ inventory_hostname }}</h1>
              <p>This server was configured using Terraform + Ansible.</p>
          </body>
          </html>

    - name: Verify Apache
      ansible.builtin.uri:
        url: http://localhost
        status_code: 200
      register: apache_check

    - name: Display Apache status
      ansible.builtin.debug:
        msg: "Apache is running successfully on {{ inventory_hostname }}"
PLAYBOOK

    # Set permissions
    chmod 755 /etc/ansible
    chmod 644 /etc/ansible/ansible.cfg
    chmod 644 /etc/ansible/inventory/hosts
    chmod 644 /etc/ansible/playbooks/ping.yml
    chmod 644 /etc/ansible/playbooks/webserver.yml

    # Save installation information
    cat > /etc/ansible/INSTALLATION_COMPLETE <<'STATUS'
    Ansible installation completed successfully.
    STATUS

  EOF

  depends_on = [
    aws_instance.web
  ]

  tags = {
    Name = "${var.project_name}-ansible-server"
    Role = "ansible-control"
  }
}