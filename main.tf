provider "aws" {
  region = var.aws_region
}

resource "aws_vpc" "terra_vpc" {
  cidr_block       = var.vpc_cidr_block
  instance_tenancy = "default"

  tags = {
    Name = "terra-vpc"
  }
}

resource "aws_subnet" "public" {
  for_each = { for i, cidr in slice(var.public_subnet_cidr_blocks, 0, var.public_subnet_count) : i => cidr }

  vpc_id                  = aws_vpc.terra_vpc.id
  cidr_block              = each.value
  availability_zone       = data.aws_availability_zones.available.names[tonumber(each.key)]
  map_public_ip_on_launch = true

  tags = {
    Name = "terra-public-subnet-0${tonumber(each.key) + 1}"
  }
}

resource "aws_subnet" "private" {
  for_each = { for i, cidr in slice(var.private_subnet_cidr_blocks, 0, var.private_subnet_count) : i => cidr }

  vpc_id            = aws_vpc.terra_vpc.id
  cidr_block        = each.value
  availability_zone = element(data.aws_availability_zones.available.names, length(data.aws_availability_zones.available.names) - var.private_subnet_count + tonumber(each.key))

  tags = {
    Name = "terra-private-subnet-0${tonumber(each.key) + 1}"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.terra_vpc.id

  tags = {
    Name = "terra-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.terra_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "terra-public-route-table"
  }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = {
    Name = "nat-eip"
  }
}

resource "aws_nat_gateway" "ngw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "terra-ngw"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.terra_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.ngw.id
  }

  tags = {
    Name = "terra-private-route-table"
  }
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "frontend" {
  name        = "terra-frontend-web-sg"
  description = "Security Group for frontend web server"
  vpc_id      = aws_vpc.terra_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "terra-frontend-web-sg"
  }
}

resource "aws_security_group" "backend" {
  name        = "terra-backend-sg"
  description = "Security Group for backend server"
  vpc_id      = aws_vpc.terra_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "ingress" {
    for_each = aws_subnet.public
    content {
      from_port   = 8000
      to_port     = 8000
      protocol    = "tcp"
      cidr_blocks = [ingress.value.cidr_block]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "terra-backend-sg"
  }
}

resource "aws_security_group" "database" {
  name        = "terra-database-sg"
  description = "Security Group for database server"
  vpc_id      = aws_vpc.terra_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "ingress" {
    for_each = aws_subnet.public
    content {
      from_port = 3306
      to_port = 3306
      protocol = "tcp"
      cidr_blocks = [ingress.value.cidr_block]
    }
  }

  dynamic "ingress" {
    for_each = aws_subnet.private
    content {
      from_port   = 3306
      to_port     = 3306
      protocol    = "tcp"
      cidr_blocks = [ingress.value.cidr_block]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "terra-database-sg"
  }
}

# Create an SSH key
resource "tls_private_key" "rsa" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Define the local file resource and Store the Private key in local
resource "local_file" "terra_chatapp_local" {
  content  = tls_private_key.rsa.private_key_pem
  filename = "${path.module}/terra-chatapp-key.pem"

  provisioner "local-exec" {
    command = "cmd.exe /C ${path.module}\\change_permissions.cmd"
  }
}

# Define the key pair resource
resource "aws_key_pair" "terra_chatapp_key" {
  key_name   = "terra-chatapp-key"
  public_key = tls_private_key.rsa.public_key_openssh

}

# Create the Frontend instance
resource "aws_instance" "frontend" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.ec2_instance_type
  subnet_id                   = aws_subnet.public[0].id # First public subnet
  key_name                    = aws_key_pair.terra_chatapp_key.key_name
  vpc_security_group_ids      = [aws_security_group.frontend.id]
  associate_public_ip_address = true

  tags = {
    Name = "terra-frontend-server"
  }

  connection {
    type = "ssh"
    user = "ubuntu"
    // private_key = file("${path.module}/terra-chatapp-key.pem")
    //private_key = tls_private_key.rsa.private_key_pem
    private_key = file("${local_file.terra_chatapp_local.filename}")
    host        = self.public_ip
  }

  provisioner "file" {
    source      = "${path.module}/terra-chatapp-key.pem"
    destination = "/home/ubuntu/terra-chatapp-key.pem"
  }


  provisioner "file" {
    source      = "${path.module}/chatapp.conf"
    destination = "/home/ubuntu/chatapp.conf"
  }

  # provisioner "file" {
  #   source = "${path.module}/env.conf"
  #   destination = "/home/ubuntu/env.conf"
  # }

  provisioner "file" {
    source = "${path.module}/chatapp.service"
    destination = "/home/ubuntu/chatapp.service"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo chmod 400 /home/ubuntu/terra-chatapp-key.pem"
    ]
  }

  depends_on = [
    local_file.terra_chatapp_local, 
    aws_instance.database
  ]
}

# Create the Backend instance
resource "aws_instance" "backend" {
  ami                         = data.aws_ami.backend.id
  instance_type               = var.ec2_instance_type
  subnet_id                   = aws_subnet.private[0].id # First private subnet
  key_name                    = aws_key_pair.terra_chatapp_key.key_name
  vpc_security_group_ids      = [aws_security_group.backend.id]
  associate_public_ip_address = false

  tags = {
    Name = "terra-backend-server"
  }
}

resource "aws_instance" "database" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.ec2_instance_type
  // subnet_id = aws_subnet.private[length(aws_subnet.private) - 1].id  # Last private subnet
  subnet_id                   = aws_subnet.private[0].id // t2.micro not supported in ap-south-1c
  key_name                    = aws_key_pair.terra_chatapp_key.key_name
  vpc_security_group_ids      = [aws_security_group.database.id]
  associate_public_ip_address = false

  tags = {
    Name = "terra-database-server"
  }

  depends_on = [
    aws_nat_gateway.ngw,
    aws_route_table_association.private
  ]
}

resource "null_resource" "configure_database" {

  depends_on = [
    aws_instance.frontend,
    aws_instance.backend,
    aws_instance.database
  ]

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("${local_file.terra_chatapp_local.filename}")
    host        = aws_instance.frontend.public_ip
    bastion_host = aws_instance.frontend.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "ssh -o StrictHostKeyChecking=no -i /home/ubuntu/terra-chatapp-key.pem ubuntu@${aws_instance.database.private_ip} 'sudo apt-get update'",
      "ssh -o StrictHostKeyChecking=no -i /home/ubuntu/terra-chatapp-key.pem ubuntu@${aws_instance.database.private_ip} 'sudo apt-get install mysql-server -y'"
    ]
  }

  provisioner "remote-exec" {
    inline = [
      "ssh -o StrictHostKeyChecking=no -i /home/ubuntu/terra-chatapp-key.pem ubuntu@${aws_instance.database.private_ip} 'sudo mysql_secure_installation <<< $'\\''n\\ny\\ny\\ny\\ny\\n'\\'''"
    ]
  }

  # provisioner "remote-exec" {
  #   inline = [
  #     "ssh -o StrictHostKeyChecking=no -i /home/ubuntu/terra-chatapp-key.pem ubuntu@${aws_instance.database.private_ip} \"sudo mysql -e 'CREATE DATABASE IF NOT EXISTS chatapp;'\"",
  #     "ssh -o StrictHostKeyChecking=no -i /home/ubuntu/terra-chatapp-key.pem ubuntu@${aws_instance.database.private_ip} \"sudo mysql -e 'CREATE USER IF NOT EXISTS \\'chatapp\\'@\\'%\\' IDENTIFIED BY \\'J.YqwX83zz\\';'\"",
  #     "ssh -o StrictHostKeyChecking=no -i /home/ubuntu/terra-chatapp-key.pem ubuntu@${aws_instance.database.private_ip} \"sudo mysql -e 'GRANT ALL PRIVILEGES ON chatapp.* TO \\'chatapp\\'@\\'%\\';'\"",
  #     "ssh -o StrictHostKeyChecking=no -i /home/ubuntu/terra-chatapp-key.pem ubuntu@${aws_instance.database.private_ip} \"sudo mysql -e 'FLUSH PRIVILEGES;'\"",
  #   ]
  # }

  provisioner "remote-exec" {
    inline = [
      "ssh -o StrictHostKeyChecking=no -i /home/ubuntu/terra-chatapp-key.pem ubuntu@${aws_instance.database.private_ip} \"sudo mysql -e \\\"CREATE DATABASE IF NOT EXISTS chatapp; CREATE USER IF NOT EXISTS 'chatapp' IDENTIFIED BY 'J.YqwX83zz'; GRANT ALL PRIVILEGES ON chatapp.* TO 'chatapp'@'%'; FLUSH PRIVILEGES;\\\"\""
    ]
  }

  provisioner "remote-exec" {
    inline = [
      "ssh -o StrictHostKeyChecking=no -i /home/ubuntu/terra-chatapp-key.pem ubuntu@${aws_instance.database.private_ip} 'sudo sed -i \"s/^bind-address\\\\s*=\\\\s*127.0.0.1/bind-address = 0.0.0.0/\" /etc/mysql/mysql.conf.d/mysqld.cnf'",
      "ssh -o StrictHostKeyChecking=no -i /home/ubuntu/terra-chatapp-key.pem ubuntu@${aws_instance.database.private_ip} 'sudo sed -i \"s/^mysqlx-bind-address\\\\s*=\\\\s*127.0.0.1/mysqlx-bind-address = 0.0.0.0/\" /etc/mysql/mysql.conf.d/mysqld.cnf'",
      "ssh -o StrictHostKeyChecking=no -i /home/ubuntu/terra-chatapp-key.pem ubuntu@${aws_instance.database.private_ip} 'sudo systemctl restart mysql'"
    ]
  }
}

resource "null_resource" "configure_backend" {
  depends_on = [ 
    aws_instance.database,
    aws_instance.backend,
    null_resource.configure_database
  ]

  connection {
    type = "ssh"
    user = "ubuntu"
    private_key = file("${local_file.terra_chatapp_local.filename}")
    host = aws_instance.frontend.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "scp -o StrictHostKeyChecking=no -i /home/ubuntu/terra-chatapp-key.pem /home/ubuntu/chatapp.service ubuntu@${aws_instance.backend.private_ip}:/home/ubuntu/chatapp.service",
      "ssh -o StrictHostKeyChecking=no -i /home/ubuntu/terra-chatapp-key.pem ubuntu@${aws_instance.backend.private_ip} 'sudo apt-get update'",
      "ssh -o StrictHostKeyChecking=no -i /home/ubuntu/terra-chatapp-key.pem ubuntu@${aws_instance.backend.private_ip} 'sudo apt-get install python3 python3-pip python3-dev default-libmysqlclient-dev build-essential -y'",
      "ssh -o StrictHostKeyChecking=no -i /home/ubuntu/terra-chatapp-key.pem ubuntu@${aws_instance.backend.private_ip} 'cd /home/ubuntu && git clone https://github.com/Akshay444Kumar/chatapp.git app'",
      "ssh -o StrictHostKeyChecking=no -i /home/ubuntu/terra-chatapp-key.pem ubuntu@${aws_instance.backend.private_ip} 'cd /home/ubuntu/app && pip3 install virtualenv'",
      "ssh -o StrictHostKeyChecking=no -i /home/ubuntu/terra-chatapp-key.pem ubuntu@${aws_instance.backend.private_ip} 'cd /home/ubuntu/app && /home/ubuntu/.local/bin/virtualenv -p /usr/bin/python3 venv'",
      "ssh -o StrictHostKeyChecking=no -i /home/ubuntu/terra-chatapp-key.pem ubuntu@${aws_instance.backend.private_ip} 'cd /home/ubuntu/app && source venv/bin/activate && pip3 install -r requirements.txt && pip3 install mysqlclient'",
      "ssh -o StrictHostKeyChecking=no -i /home/ubuntu/terra-chatapp-key.pem ubuntu@${aws_instance.backend.private_ip} \"sudo sed -i 's/CHATDB/chatapp/g' /home/ubuntu/app/fundoo/fundoo/settings.py\"",
      "ssh -o StrictHostKeyChecking=no -i /home/ubuntu/terra-chatapp-key.pem ubuntu@${aws_instance.backend.private_ip} \"sudo sed -i 's/CHATUSER/chatapp/g' /home/ubuntu/app/fundoo/fundoo/settings.py\"",
      "ssh -o StrictHostKeyChecking=no -i /home/ubuntu/terra-chatapp-key.pem ubuntu@${aws_instance.backend.private_ip} \"sudo sed -i 's/CHATPASSWORD/J.YqwX83zz/g' /home/ubuntu/app/fundoo/fundoo/settings.py\"",
      "ssh -o StrictHostKeyChecking=no -i /home/ubuntu/terra-chatapp-key.pem ubuntu@${aws_instance.backend.private_ip} \"sudo sed -i 's/CHATHOST/${aws_instance.database.private_ip}/g' /home/ubuntu/app/fundoo/fundoo/settings.py\"",
      "ssh -o StrictHostKeyChecking=no -i /home/ubuntu/terra-chatapp-key.pem ubuntu@${aws_instance.backend.private_ip} 'cd /home/ubuntu/app && source venv/bin/activate && python3 fundoo/manage.py makemigrations && python3 fundoo/manage.py migrate'",
      "ssh -o StrictHostKeyChecking=no -i /home/ubuntu/terra-chatapp-key.pem ubuntu@${aws_instance.backend.private_ip} 'sudo mv /home/ubuntu/chatapp.service /lib/systemd/system/chatapp.service && sudo chown root. /lib/systemd/system/chatapp.service'",
      "ssh -o StrictHostKeyChecking=no -i /home/ubuntu/terra-chatapp-key.pem ubuntu@${aws_instance.backend.private_ip} 'sudo systemctl daemon-reload && sudo systemctl enable chatapp.service && sudo systemctl start chatapp.service'"
    ] 
  }
}

resource "null_resource" "configure_frontend" {

  depends_on = [ 
    aws_instance.database,
    aws_instance.backend,
    aws_instance.frontend,
    null_resource.configure_database,
    null_resource.configure_backend
   ]

  connection {
    type = "ssh"
    user = "ubuntu"
    private_key = file("${local_file.terra_chatapp_local.filename}")
    host = aws_instance.frontend.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install nginx -y",
      "sudo mv /home/ubuntu/chatapp.conf /etc/nginx/sites-available/chatapp.conf",
      "sudo sed -i 's|BACKEND_IP|${aws_instance.backend.private_ip}|g' /etc/nginx/sites-available/chatapp.conf",
      "sudo unlink /etc/nginx/sites-enabled/default",
      "sudo ln -s /etc/nginx/sites-available/chatapp.conf /etc/nginx/sites-enabled/",
      "sudo systemctl enable nginx",
      "sudo systemctl restart nginx"
    ]
  }
}
