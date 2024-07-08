variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "ap-south-1"
}

variable "environment" {
  description = "Environment for application deployment"
  type = string  
}

variable "vpc_cidr_block" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_count" {
  description = "Number of public subnets"
  type        = number
  default     = 2
}

variable "private_subnet_count" {
  description = "Number of private subnets"
  type        = number
  default     = 2
}

variable "public_subnet_cidr_blocks" {
  description = "Available CIDR blocks for public subnet"
  type        = list(string)
}

variable "private_subnet_cidr_blocks" {
  description = "Available CIDR blocks for private subnet"
  type        = list(string)
}

variable "ec2_instance_type" {
  description = "AWS EC2 instance type"
  type        = string
  default     = "t2.micro"
}



