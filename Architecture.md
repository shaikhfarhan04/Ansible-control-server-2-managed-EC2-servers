
## Architecture

![Image](https://images.openai.com/static-rsc-4/NCBnFNlx4OQyFUSZI_ta3z-QInJNXrWvC1IbaXRsHHrO3WT5K3JyXp61zDgpDyjT-wy4T1zoENnin1IOk_W1s8HUEdH09A35ZoyS7qhxQt9pbfZPYQ490B7qCJ6hDE2vetYR9S03z2gE3roM3DwmpmZacnQ7av_QjsEJSJdfw71FfVntLNGc7gxu_4jcZDuN?purpose=fullsize)

![Image](https://images.openai.com/static-rsc-4/go_dbQZXdzmxWlzIUEg9WpWgod1q9Rwg90laH1_JLMvbGQyxL7reHQe78w1znUBnXuiQew2eN7kxRFtpFi4yIhFOp2rY0RQnInJom3YgdWYGvuK2P1rfKJKuTdU_LT3St9hod9xhVzWLzqC75LzSdxW4s-UfgJAjV6oEvhsI9TiZFHpg1nDNtUrFMCZ2OUQO?purpose=fullsize)

![Image](https://images.openai.com/static-rsc-4/2Gt3-QhKKT3HLhIzj9dMfx0fhoiapVoUaGKDRmKTL8KeR5dtR-Nlugb9oxmipdVZj_4YsSlGkX_ZmrK2VTl5IpW9i675DnlWlO2fqNowE5doAc0B-7f7PWx4MwxNWBpx1xfFe4tOgSxyBkJhBf6weWcyKnOuyr_LgAd69tmH3peuHrLtYFifp8xbmBI6qi-X?purpose=fullsize)

![Image](https://images.openai.com/static-rsc-4/WKrO9amLUr_k380CK3u6svM8kCni9ll7NsCHQxCH7T111jth_oamEXjHcPNgyX4JHa2lRc78iJNcVMh4n8m5GxbEMv6x7oe-l3CUZwf1CxjXjYLjd0E6jzt0KnxLNTdNWIItxkNW_e5BBQTcvLLrgytF_GpwYnlpFOxYPsxgkLjML-PzD-RvE19hSTm-afnR?purpose=fullsize)

```text
                    AWS VPC
                       |
          +------------+------------+
          |            |            |
          |            |            |
   Ansible Server   Web Server 1  Web Server 2
   t3.medium       t3.micro      t3.micro
   Control Node    Managed Node   Managed Node
          |
          | SSH
          +--------------------+
                               |
                         Private/Public IP
```

# 1. Create 3 EC2 instances

Create **3 EC2 instances** in the same VPC/subnet.

| Server         | Instance  | Purpose      |
| -------------- | --------- | ------------ |
| Ansible-Server | t3.medium | Control node |
| Web-Server-1   | t3.micro  | Managed node |
| Web-Server-2   | t3.micro  | Managed node |

Use the **same key pair** for all three instances.

For example:

```text
Key pair: ansible-key
AMI: Amazon Linux 2023
VPC: same VPC
Subnet: same subnet
```

## Security Group

For a simple lab, configure:

```text
SSH   TCP 22   Your IP
HTTP  TCP 80   0.0.0.0/0
```

For the Ansible server, SSH access from your IP is enough.

For the two web servers, you can additionally allow SSH from the Ansible server's security group.

---

# 2. Connect to Ansible Server

From your Windows machine:

```bash
ssh -i ansible-key.pem ec2-user@<ANSIBLE_SERVER_PUBLIC_IP>
```

Example:

```bash
ssh -i ansible-key.pem ec2-user@54.123.45.67
```

---

# 3. Update the Ansible Server

```bash
sudo yum update -y
```

Check Python:

```bash
python3 --version
```

Check pip:

```bash
pip3 --version
```

If pip isn't installed:

```bash
sudo dnf install python3-pip -y
```

---

# 4. Install Ansible

I recommend:

```bash
sudo pip3 install ansible
```

Then:

```bash
ansible --version
```

You should see something similar to:

```text
ansible [core ...]
  python version = 3.x.x
```

Also install useful utilities:

```bash
sudo dnf install tree -y
```

---

# 5. Create Ansible directory structure

The assignment specifically uses:

```text
/etc/ansible
```

Create it:

```bash
sudo mkdir -p /etc/ansible
```

Then:

```bash
cd /etc/ansible
```

Create directories:

```bash
sudo mkdir inventory playbooks aws
```

Create files:

```bash
sudo touch inventory/hosts
sudo touch playbooks/ping.yml
sudo touch aws/ansible.pem
sudo touch ansible.cfg
```

Check:

```bash
tree /etc/ansible
```

Expected:

```text
/etc/ansible
├── ansible.cfg
├── aws
│   └── ansible.pem
├── inventory
│   └── hosts
└── playbooks
    └── ping.yml
```

---

# 6. Copy your `.pem` key

This is one of the most important steps.

Ansible Server needs the private key to SSH into Web Server 1 and Web Server 2.

From your **Windows machine**, copy the key to the Ansible server.

For example with `scp`:

```bash
scp -i ansible-key.pem ansible-key.pem ec2-user@<ANSIBLE_SERVER_PUBLIC_IP>:/home/ec2-user/
```

Then SSH into Ansible server:

```bash
ssh -i ansible-key.pem ec2-user@<ANSIBLE_SERVER_PUBLIC_IP>
```

Move the key:

```bash
sudo mv /home/ec2-user/ansible-key.pem /etc/ansible/aws/ansible.pem
```

Set permissions:

```bash
sudo chmod 400 /etc/ansible/aws/ansible.pem
```

Verify:

```bash
ls -lah /etc/ansible/aws/
```

You should see:

```text
-r-------- 1 root root ... ansible.pem
```

---

# 7. Configure inventory

Edit:

```bash
sudo vi /etc/ansible/inventory/hosts
```

Put the **private IP addresses** of your two managed EC2 instances:

```ini
[webservers]
web1 ansible_host=10.0.1.20
web2 ansible_host=10.0.1.21
```

For example:

```ini
[webservers]
web1 ansible_host=10.0.1.20
web2 ansible_host=10.0.1.21
```

### Why private IP?

Because all three servers are inside the same VPC.

Ansible Server:

```text
10.0.1.10
```

Web Server 1:

```text
10.0.1.20
```

Web Server 2:

```text
10.0.1.21
```

Ansible communicates:

```text
Ansible Server
     |
     | SSH TCP/22
     |
     +----> 10.0.1.20
     |
     +----> 10.0.1.21
```

---

# 8. Configure `ansible.cfg`

Edit:

```bash
sudo vi /etc/ansible/ansible.cfg
```

Use:

```ini
[defaults]
inventory = ./inventory
remote_user = ec2-user
private_key_file = aws/ansible.pem
host_key_checking = False
retry_files_enabled = False

[privilege_escalation]
become = true
become_method = sudo
become_user = root
become_ask_pass = false
```

### Important

Because `inventory` and `aws/ansible.pem` are relative paths, run Ansible from:

```bash
cd /etc/ansible
```

Alternatively, you can make the configuration more robust with absolute paths:

```ini
[defaults]
inventory = /etc/ansible/inventory/hosts
remote_user = ec2-user
private_key_file = /etc/ansible/aws/ansible.pem
host_key_checking = False
retry_files_enabled = False

[privilege_escalation]
become = true
become_method = sudo
become_user = root
become_ask_pass = false
```

I recommend the **absolute-path version** for your lab.

---

# 9. Test SSH manually

Before testing Ansible, make sure SSH works.

From Ansible server:

```bash
ssh -i /etc/ansible/aws/ansible.pem ec2-user@10.0.1.20
```

Then:

```bash
exit
```

Test Web Server 2:

```bash
ssh -i /etc/ansible/aws/ansible.pem ec2-user@10.0.1.21
```

Then:

```bash
exit
```

If both work, Ansible should be able to connect.

---

# 10. Test Ansible inventory

Go to:

```bash
cd /etc/ansible
```

Run:

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

Check:

```bash
ansible all --list-hosts
```

Expected:

```text
hosts (2):
    web1
    web2
```

---

# 11. Run Ansible ping

This is the simplest test.

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

🎉 This confirms:

```text
Ansible Server
      |
      +---- SSH ----> Web Server 1
      |
      +---- SSH ----> Web Server 2
```

---

# 12. Create `ping.yml`

Now do the assignment using a playbook.

```bash
sudo vi /etc/ansible/playbooks/ping.yml
```

Put:

```yaml
---
- name: Test Ansible connectivity
  hosts: webservers
  become: true

  tasks:
    - name: Ping managed servers
      ansible.builtin.ping:
```

Run:

```bash
cd /etc/ansible
ansible-playbook playbooks/ping.yml
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

# 13. Verify Ansible configuration

Run:

```bash
ansible --version
```

You should see the configuration path:

```text
config file = /etc/ansible/ansible.cfg
```

This is important for your assignment.

---

# 14. Optional: Install Apache on both servers

Since your repository is called **ansible-terraform-webservers**, it is useful to demonstrate Ansible automation beyond ping.

Create:

```bash
sudo vi /etc/ansible/playbooks/webserver.yml
```

Use:

```yaml
---
- name: Configure web servers
  hosts: webservers
  become: true

  tasks:
    - name: Install Apache
      ansible.builtin.dnf:
        name: httpd
        state: present

    - name: Start Apache
      ansible.builtin.service:
        name: httpd
        state: started
        enabled: true

    - name: Create index page
      ansible.builtin.copy:
        content: |
          <html>
          <head>
            <title>Ansible Web Server</title>
          </head>
          <body>
            <h1>Hello from {{ inventory_hostname }}</h1>
            <p>Configured using Ansible.</p>
          </body>
          </html>
        dest: /var/www/html/index.html
        mode: '0644'
```

Run:

```bash
ansible-playbook playbooks/webserver.yml
```

Then:

```bash
ansible webservers -m shell -a "systemctl status httpd --no-pager"
```

---

# 15. Useful Ansible commands for your assignment

### Check all hosts

```bash
ansible all --list-hosts
```

### Ping all hosts

```bash
ansible all -m ping
```

### Ping only webservers

```bash
ansible webservers -m ping
```

### Check uptime

```bash
ansible all -m command -a "uptime"
```

### Check OS

```bash
ansible all -m command -a "cat /etc/os-release"
```

### Check disk

```bash
ansible all -m command -a "df -h"
```

### Check memory

```bash
ansible all -m command -a "free -h"
```

### Run playbook

```bash
ansible-playbook playbooks/ping.yml
```

### List inventory

```bash
ansible-inventory --graph
```

---

# 16. Troubleshooting

## Error: `UNREACHABLE`

Example:

```text
web1 | UNREACHABLE!
```

Test SSH:

```bash
ssh -i /etc/ansible/aws/ansible.pem ec2-user@10.0.1.20
```

If SSH fails, check:

1. Private IP is correct.
2. Both EC2 instances are in the same VPC.
3. Security group allows SSH.
4. `.pem` permissions are correct.
5. Username is `ec2-user`.
6. Route tables/NACLs are not blocking traffic.

---

## Error: Permission denied (publickey)

Check:

```bash
ls -l /etc/ansible/aws/ansible.pem
```

Set:

```bash
sudo chmod 400 /etc/ansible/aws/ansible.pem
```

Then:

```bash
ssh -i /etc/ansible/aws/ansible.pem ec2-user@<PRIVATE-IP>
```

---

## Error: `Host key verification failed`

Your configuration contains:

```ini
host_key_checking = False
```

Make sure Ansible is actually loading your configuration:

```bash
ansible --version
```

Look for:

```text
config file = /etc/ansible/ansible.cfg
```

---

## Error: `sudo: cd: command not found`

Don't do:

```bash
sudo cd /etc/ansible
```

`cd` is a shell built-in.

Use:

```bash
cd /etc/ansible
```

For creating/editing files:

```bash
sudo vi /etc/ansible/ansible.cfg
```

---

# 17. Final project structure

Your Ansible server should finally look like:

```text
/etc/ansible/
│
├── ansible.cfg
│
├── inventory/
│   └── hosts
│
├── playbooks/
│   ├── ping.yml
│   └── webserver.yml
│
└── aws/
    └── ansible.pem
```

And your AWS infrastructure:

```text
AWS VPC
│
├── Ansible Server
│   └── t3.medium
│       └── Ansible Control Node
│
├── Web Server 1
│   └── t3.micro
│
└── Web Server 2
    └── t3.micro
```

### Assignment completion checklist

* [ ] Create 3 EC2 instances
* [ ] Put all 3 in same VPC
* [ ] Install Python/pip on Ansible server
* [ ] Install Ansible
* [ ] Create `/etc/ansible`
* [ ] Create `inventory`, `playbooks`, `aws`
* [ ] Copy `.pem` to `aws/ansible.pem`
* [ ] Configure `ansible.cfg`
* [ ] Add Web Server private IPs to inventory
* [ ] Test SSH
* [ ] Run `ansible all -m ping`
* [ ] Create `ping.yml`
* [ ] Run `ansible-playbook playbooks/ping.yml`
* [ ] Optionally install Apache on both web servers
* [ ] Push the completed project to GitHub

**Git repository for the assignment:** [atulkamble/ansible-terraform-webservers](https://github.com/atulkamble/ansible-terraform-webservers.git?utm_source=chatgpt.com)
