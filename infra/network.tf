# ===== DATA SOURCES =====
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_subnet" "default" {
  id = data.aws_subnets.default.ids[0]
}

# ===== SECURITY GROUPS =====
resource "aws_security_group" "minecraft" {
  name_prefix = "minecraft-server-"
  vpc_id      = data.aws_vpc.default.id
  description = "Security group for Minecraft server"

  # SSH access from admin IP only
  ingress {
    description = "SSH from admin IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_ip]
  }

  # Minecraft server port
  ingress {
    description = "Minecraft server port"
    from_port   = 25565
    to_port     = 25565
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # RCON port (localhost only)
  ingress {
    description = "RCON port"
    from_port   = 25575
    to_port     = 25575
    protocol    = "tcp"
    self        = true
  }

  # All outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "minecraft-security-group"
  }
}

# ===== ELASTIC IP =====
resource "aws_eip" "minecraft" {
  domain = "vpc"
  
  tags = {
    Name = "minecraft-eip"
  }
}
