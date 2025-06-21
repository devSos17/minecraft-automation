variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "instance_type" {
  description = "EC2 instance type for Minecraft server"
  type        = string
  default     = "t3.small"
}

variable "spot_price" {
  description = "Maximum spot price"
  type        = string
  default     = "0.015"
}

variable "admin_ip" {
  description = "Admin IP for SSH access"
  type        = string
  validation {
    condition     = can(cidrhost(var.admin_ip, 0))
    error_message = "Admin IP must be a valid CIDR block (e.g., 192.168.1.100/32)."
  }
}

variable "key_name" {
  description = "EC2 Key Pair name for SSH access"
  type        = string
}

variable "minecraft_version" {
  description = "Minecraft server version"
  type        = string
  default     = "1.20.4"
}

variable "cognito_domain_prefix" {
  description = "Cognito domain prefix (must be unique)"
  type        = string
}

variable "frontend_domain" {
  description = "Custom domain for frontend (optional)"
  type        = string
  default     = ""
}
