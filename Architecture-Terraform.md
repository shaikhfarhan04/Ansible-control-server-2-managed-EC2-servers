This version creates:

* 1 Ansible control EC2 — `t3.medium`
* 2 managed web EC2s — `t3.micro`
* Custom VPC
* Public subnet
* Internet Gateway
* Route table
* Security groups
* Automatically generated SSH key pair
* Amazon Linux 2023
* Ansible automatically installed on the control server
* `/etc/ansible` structure automatically created
* `inventory/hosts`
* `ansible.cfg`
* `ping.yml`
* Apache installation playbook
* Terraform outputs for all IP addresses

I'm using AWS's public SSM parameter for the latest Amazon Linux 2023 x86_64 AMI rather than hard-coding an AMI ID. AWS documents that this parameter is region-aware and points to the current AL2023 AMI. ([AWS Documentation][1])

Terraform's AWS provider supports `aws_instance`, `aws_key_pair`, user data, and VPC resources used below. ([Terraform Registry][2])

---

# 1. Final architecture

```text
                         AWS us-east-1
                              |
                         Custom VPC
                       10.0.0.0/16
                              |
                     Public Subnet
                      10.0.1.0/24
                              |
              +---------------+---------------+
              |               |               |
              |               |               |
        Ansible Server    Web Server 1    Web Server 2
        t3.medium         t3.micro        t3.micro
              |               |               |
              +------- SSH ---+---------------+
                      |
                 Ansible Control
```

The final setup will be:

```text
Ansible Server
10.0.1.x
    |
    +---- SSH ----> Web Server 1
    |
    +---- SSH ----> Web Server 2
```

---

# 2. Create project directory

On your **Windows 11 + VS Code**:

```powershell
mkdir ansible-terraform
cd ansible-terraform
code .
```

Create this structure:

```text
ansible-terraform/
│
├── provider.tf
├── variables.tf
├── vpc.tf
├── security-group.tf
├── key-pair.tf
├── ec2.tf
├── outputs.tf
├── terraform.tfvars
├── .gitignore
│
└── ansible/
    ├── inventory/
    │   └── hosts
    │
    ├── playbooks/
    │   ├── ping.yml
    │   └── webserver.yml
    │
    └── ansible.cfg
```

The `ansible` files will actually be generated automatically on the Ansible EC2, but I've included them in the project so your GitHub repository clearly demonstrates the assignment.

---

# 3. `provider.tf`

Create:

```text
provider.tf
```

Paste:

```hcl
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }

    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "ansible-terraform-webservers"
      Environment = "lab"
      ManagedBy   = "Terraform"
    }
  }
}
```

---

# 4. `variables.tf`

Create:

```text
variables.tf
```

Paste:

```hcl
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "ansible-terraform"
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "Public subnet CIDR"
  type        = string
  default     = "10.0.1.0/24"
}

variable "availability_zone" {
  description = "Availability Zone"
  type        = string
  default     = "us-east-1a"
}

variable "ansible_instance_type" {
  description = "Ansible control server instance type"
  type        = string
  default     = "t3.medium"
}

variable "web_instance_type" {
  description = "Web server instance type"
  type        = string
  default     = "t3.micro"
}

variable "admin_cidr" {
  description = "CIDR allowed to SSH into Ansible server. Change this to your public IP/32."
  type        = string
  default     = "0.0.0.0/0"
}
```

### Important

For a lab, `0.0.0.0/0` works.

For security, after finding your public IP, change:

```hcl
admin_cidr = "YOUR_PUBLIC_IP/32"
```

For example:

```hcl
admin_cidr = "49.205.100.25/32"
```

---

# 5. `vpc.tf`

Create:

```text
vpc.tf
```

Paste:

```hcl
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-route-table"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
```

---

# 6. `security-group.tf`

Create:

```text
security-group.tf
```

Paste:

```hcl
resource "aws_security_group" "ansible" {
  name        = "${var.project_name}-ansible-sg"
  description = "Security group for Ansible control server"
  vpc_id      = aws_vpc.main.id

  # SSH from administrator
  ingress {
    description = "SSH from administrator"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  # HTTP
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-ansible-sg"
  }
}


resource "aws_security_group" "web" {
  name        = "${var.project_name}-web-sg"
  description = "Security group for Ansible managed web servers"
  vpc_id      = aws_vpc.main.id

  # SSH ONLY from Ansible server
  ingress {
    description     = "SSH from Ansible control server"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.ansible.id]
  }

  # HTTP
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-web-sg"
  }
}
```

This is better than opening SSH to the world on the web servers.

```text
Internet
   |
   +---- SSH ----> Ansible Server
                       |
                       +---- SSH ----> Web 1
                       |
                       +---- SSH ----> Web 2
```

---

# 7. `key-pair.tf`

Here we're automatically generating the SSH key using Terraform.

Create:

```text
key-pair.tf
```

Paste:

```hcl
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
```

This gives you:

```text
ansible-terraform.pem
```

in your Terraform directory.

### Important security note

This is excellent for a **lab assignment**, but don't use this approach for production because the private key is stored in Terraform state.

For this assignment, it's convenient because Terraform can automatically:

```text
Generate key
     ↓
Register public key with AWS
     ↓
Save private key locally
     ↓
Install same private key on Ansible server
     ↓
Ansible SSH → Web servers
```

---

# 8. `ec2.tf`

This is the main file.

Create:

```text
ec2.tf
```

Paste:

```hcl
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
```

### Important

The web servers are created first because the Ansible server's `user_data` needs their private IP addresses.

---

# 9. `outputs.tf`

Create:

```text
outputs.tf
```

Paste:

```hcl
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
```

---

# 10. `terraform.tfvars`

Create:

```text
terraform.tfvars
```

Paste:

```hcl
aws_region            = "us-east-1"
project_name          = "ansible-terraform"
vpc_cidr              = "10.0.0.0/16"
public_subnet_cidr    = "10.0.1.0/24"
availability_zone     = "us-east-1a"

ansible_instance_type = "t3.medium"
web_instance_type     = "t3.micro"

# Change this to YOUR_PUBLIC_IP/32 for better security.
admin_cidr = "0.0.0.0/0"
```

For your assignment, this will work immediately.

---

# 11. `.gitignore`

Very important because we don't want to push the private key or Terraform state to GitHub.

Create:

```text
.gitignore
```

Paste:

```gitignore
# Terraform
.terraform/
*.tfstate
*.tfstate.*
.terraform.lock.hcl

# Terraform variables containing secrets
*.tfvars
!example.tfvars

# Generated private key
*.pem

# Crash logs
crash.log
crash.*.log

# VS Code
.vscode/

# OS files
.DS_Store
Thumbs.db
```

---

# 12. Ansible `inventory/hosts`

Create:

```text
ansible/inventory/hosts
```

Paste:

```ini
[webservers]
web1 ansible_host=10.0.1.20
web2 ansible_host=10.0.1.21
```

These are examples for your GitHub repository.

Terraform will generate the **real IPs** automatically on the EC2 server.

---

# 13. Ansible `ansible.cfg`

Create:

```text
ansible/ansible.cfg
```

Paste:

```ini
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
```

---

# 14. `ping.yml`

Create:

```text
ansible/playbooks/ping.yml
```

Paste:

```yaml
---
- name: Test Ansible connectivity
  hosts: webservers
  become: true

  tasks:
    - name: Ping managed servers
      ansible.builtin.ping:
```

---

# 15. `webserver.yml`

Create:

```text
ansible/playbooks/webserver.yml
```

Paste:

```yaml
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

    - name: Display success message
      ansible.builtin.debug:
        msg: "Apache is running successfully on {{ inventory_hostname }}"
```

---

# 16. Terraform authentication

Before running Terraform, make sure AWS CLI is configured.

On Windows PowerShell:

```powershell
aws configure
```

Enter:

```text
AWS Access Key ID:
AWS Secret Access Key:
Default region name:
us-east-1
Default output format:
json
```

Check:

```powershell
aws sts get-caller-identity
```

You should receive your AWS account information.

Terraform can use the AWS CLI credentials/shared configuration, which is one of the supported AWS provider authentication mechanisms. ([Terraform Registry][3])

---

# 17. Terraform initialization

From your project directory:

```powershell
terraform init
```

You should see providers being installed:

```text
Initializing the backend...
Initializing provider plugins...

- Installing hashicorp/aws...
- Installing hashicorp/tls...
- Installing hashicorp/local...

Terraform has been successfully initialized!
```

---

# 18. Format Terraform

```powershell
terraform fmt
```

---

# 19. Validate

```powershell
terraform validate
```

Expected:

```text
Success! The configuration is valid.
```

---

# 20. Plan

Run:

```powershell
terraform plan
```

You should see resources similar to:

```text
Plan: 13 to add, 0 to change, 0 to destroy.
```

The exact number can vary with provider/resource details.

---

# 21. Apply

Now:

```powershell
terraform apply
```

Terraform asks:

```text
Do you want to perform these actions?
  Enter a value:
```

Enter:

```text
yes
```

Terraform will create:

```text
VPC
 |
 +-- Subnet
 |
 +-- Internet Gateway
 |
 +-- Route Table
 |
 +-- Security Groups
 |
 +-- Key Pair
 |
 +-- Web Server 1
 |
 +-- Web Server 2
 |
 +-- Ansible Server
```

---

# 22. Check Terraform outputs

After completion:

```powershell
terraform output
```

You should get something like:

```text
ansible_public_ip = "54.x.x.x"
ansible_private_ip = "10.0.1.10"

web_server_1_public_ip = "3.x.x.x"
web_server_1_private_ip = "10.0.1.20"

web_server_2_public_ip = "18.x.x.x"
web_server_2_private_ip = "10.0.1.21"
```

---

# 23. Connect to Ansible server

Terraform will generate:

```text
ansible-terraform.pem
```

Run:

```powershell
ssh -i .\ansible-terraform.pem ec2-user@<ANSIBLE_PUBLIC_IP>
```

For example:

```powershell
ssh -i .\ansible-terraform.pem ec2-user@54.123.45.67
```

---

# 24. Verify Ansible installation

On the Ansible server:

```bash
ansible --version
```

You should see:

```text
ansible [core ...]
```

Also:

```bash
which ansible
```

Expected:

```text
/usr/local/bin/ansible
```

Check Python:

```bash
python3 --version
```

Amazon Linux 2023 provides Python 3 as its system Python; AWS specifically advises not changing the `/usr/bin/python3` symlink. ([AWS Documentation][4])

---

# 25. Check Ansible directory

```bash
tree /etc/ansible
```

Expected:

```text
/etc/ansible
├── INSTALLATION_COMPLETE
├── ansible.cfg
├── aws
│   └── ansible.pem
├── inventory
│   └── hosts
└── playbooks
    ├── ping.yml
    └── webserver.yml
```

---

# 26. Check inventory

```bash
cat /etc/ansible/inventory/hosts
```

You should see something similar to:

```ini
[webservers]
web1 ansible_host=10.0.1.20
web2 ansible_host=10.0.1.21
```

These are the **private IPs** of your two EC2 servers.

---

# 27. Test SSH from Ansible server

First Web Server:

```bash
ssh -i /etc/ansible/aws/ansible.pem ec2-user@10.0.1.20
```

Exit:

```bash
exit
```

Second:

```bash
ssh -i /etc/ansible/aws/ansible.pem ec2-user@10.0.1.21
```

Exit:

```bash
exit
```

If both work, your Terraform networking + SSH setup is correct.

---

# 28. Run Ansible inventory

```bash
cd /etc/ansible
```

Then:

```bash
ansible-inventory --graph
```

Expected:

```text
@all:
  |--@ungrouped:
  |--@webservers:
  |  |--web1
  |  |--web2
```

---

# 29. Run the assignment's ping test

```bash
ansible all -m ping
```

Expected:

```text
web1 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}

web2 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

🎉 **This completes the core Ansible installation and configuration assignment.**

---

# 30. Run the ping playbook

```bash
ansible-playbook /etc/ansible/playbooks/ping.yml
```

Expected:

```text
PLAY [Test Ansible connectivity]

TASK [Ping managed servers]
ok: [web1]
ok: [web2]

PLAY RECAP
web1 : ok=1 changed=0 unreachable=0 failed=0
web2 : ok=1 changed=0 unreachable=0 failed=0
```

---

# 31. Install Apache automatically

Now run:

```bash
ansible-playbook /etc/ansible/playbooks/webserver.yml
```

Expected:

```text
PLAY [Configure Apache web servers]

TASK [Install Apache]
changed: [web1]
changed: [web2]

TASK [Start and enable Apache]
changed: [web1]
changed: [web2]

TASK [Create index page]
changed: [web1]
changed: [web2]

TASK [Verify Apache]
ok: [web1]
ok: [web2]

PLAY RECAP
web1 : ok=5 changed=3 unreachable=0 failed=0
web2 : ok=5 changed=3 unreachable=0 failed=0
```

---

# 32. Test Web Server 1

From your Windows browser:

```text
http://<WEB_SERVER_1_PUBLIC_IP>
```

You should see:

```text
Hello from web1

This server was configured using Terraform + Ansible.
```

Web Server 2:

```text
http://<WEB_SERVER_2_PUBLIC_IP>
```

You should see:

```text
Hello from web2

This server was configured using Terraform + Ansible.
```

---

# 33. Complete flow

You have now automated:

```text
                         TERRAFORM
                            |
                            v
                     Create AWS VPC
                            |
             +--------------+--------------+
             |              |              |
             v              v              v
          Subnet           IGW       Route Table
             |
             v
       Security Groups
             |
             v
       Generate SSH Key
             |
       +-----+------+
       |            |
       v            v
    Web 1         Web 2
   t3.micro      t3.micro
       |            |
       +-----+------+
             |
             v
      Ansible Server
        t3.medium
             |
             v
      Install Ansible
             |
             v
       /etc/ansible
             |
       +-----+------+
       |            |
       v            v
   inventory    ansible.cfg
       |
       v
   ansible ping
       |
       v
     "pong"
       |
       v
 Apache installation
       |
       v
 Web Server 1 + Web Server 2
```

---

# 34. Your final project

```text
ansible-terraform/
│
├── provider.tf
├── variables.tf
├── vpc.tf
├── security-group.tf
├── key-pair.tf
├── ec2.tf
├── outputs.tf
├── terraform.tfvars
├── .gitignore
│
└── ansible/
    │
    ├── ansible.cfg
    │
    ├── inventory/
    │   └── hosts
    │
    └── playbooks/
        ├── ping.yml
        └── webserver.yml
```

## Commands you need to remember

### Create everything

```powershell
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

### Connect

```powershell
ssh -i .\ansible-terraform.pem ec2-user@<ANSIBLE_PUBLIC_IP>
```

### Test Ansible

```bash
cd /etc/ansible
ansible all -m ping
```

### Run ping playbook

```bash
ansible-playbook /etc/ansible/playbooks/ping.yml
```

### Configure web servers

```bash
ansible-playbook /etc/ansible/playbooks/webserver.yml
```

### Destroy everything when finished

```powershell
terraform destroy
```

**One thing I strongly recommend before `terraform apply`:** change `admin_cidr = "0.0.0.0/0"` to your own public IP with `/32`. The web servers remain reachable on HTTP, but their SSH access will only come from the Ansible server.

[1]: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/finding-an-ami-parameter-store.html?utm_source=chatgpt.com "Reference the latest AMIs using Systems Manager public parameters - Amazon Elastic Compute Cloud"
[2]: https://registry.terraform.io/providers/hashicorp/awS/latest/docs/resources/key_pair?utm_source=chatgpt.com "aws_key_pair | Resources | hashicorp/aws | Terraform | Terraform Registry"
[3]: https://registry.terraform.io/providers/hashicorp/aws/latest/docs?utm_source=chatgpt.com "Docs overview | hashicorp/aws | Terraform | Terraform Registry"
[4]: https://docs.aws.amazon.com/linux/al2023/ug/python.html?utm_source=chatgpt.com "Python in AL2023 - Amazon Linux 2023"
