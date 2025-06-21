# ===== DATA SOURCES =====
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ===== IAM ROLES =====
resource "aws_iam_role" "minecraft_ec2_role" {
  name = "minecraft-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "minecraft-ec2-role"
  }
}

resource "aws_iam_role_policy" "minecraft_ec2_policy" {
  name = "minecraft-ec2-policy"
  role = aws_iam_role.minecraft_ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = [
          aws_ssm_parameter.minecraft_api_key.arn,
          aws_ssm_parameter.rcon_password.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeTags"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "minecraft" {
  name = "minecraft-instance-profile"
  role = aws_iam_role.minecraft_ec2_role.name
}

# ===== EC2 SPOT INSTANCE =====
resource "aws_spot_instance_request" "minecraft" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  key_name              = var.key_name
  spot_price            = var.spot_price
  wait_for_fulfillment  = true
  spot_type             = "one-time"

  vpc_security_group_ids = [aws_security_group.minecraft.id]
  subnet_id             = data.aws_subnet.default.id
  iam_instance_profile  = aws_iam_instance_profile.minecraft.name

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    api_gateway_url = "https://${aws_api_gateway_rest_api.minecraft.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_deployment.minecraft.stage_name}"
    minecraft_version = var.minecraft_version
    rcon_password_param = aws_ssm_parameter.rcon_password.name
    api_key_param = aws_ssm_parameter.minecraft_api_key.name
    region = var.aws_region
  }))

  tags = {
    Name = "minecraft-server"
    Type = "spot"
  }
}

# Associate Elastic IP with the instance
resource "aws_eip_association" "minecraft" {
  instance_id   = aws_spot_instance_request.minecraft.spot_instance_id
  allocation_id = aws_eip.minecraft.id
}

# ===== SSM PARAMETERS =====
resource "random_password" "api_key" {
  length  = 32
  special = true
}

resource "random_password" "rcon_password" {
  length  = 16
  special = false
}

resource "aws_ssm_parameter" "minecraft_api_key" {
  name        = "/minecraft/api-key"
  type        = "SecureString"
  value       = random_password.api_key.result
  description = "API key for internal Minecraft server calls"

  tags = {
    Service = "minecraft"
  }
}

resource "aws_ssm_parameter" "rcon_password" {
  name        = "/minecraft/rcon-password"
  type        = "SecureString"
  value       = random_password.rcon_password.result
  description = "RCON password for Minecraft server"

  tags = {
    Service = "minecraft"
  }
}
