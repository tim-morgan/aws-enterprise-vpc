# Example environment to create service-oriented resources in an Enterprise VPC
#
# Copyright (c) 2017 Board of Trustees University of Illinois

terraform {
  required_version = "~> 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.38"
    }
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "~> 2.2"
    }
  }

  # see backend.tf for remote state configuration
}

## Inputs (specified in terraform.tfvars)

variable "account_id" {
  description = "Your 12-digit AWS account number"
  type        = string
}

variable "region" {
  description = "AWS region for this VPC, e.g. us-east-2"
  type        = string
}

variable "vpc_short_name" {
  description = "short name of this VPC, e.g. foobar1 if the full name is aws-foobar1-vpc"
  type        = string
}

variable "ssh_ipv4_cidr_blocks" {
  description = "Optional IPv4 CIDR blocks from which to allow SSH"
  type        = list(string)
  default     = []
}

variable "ssh_ipv6_cidr_blocks" {
  description = "Optional IPv6 CIDR blocks from which to allow SSH"
  type        = list(string)
  default     = []
}

variable "ssh_public_key" {
  description = "Optional SSH public key material"
  type        = string
  default     = ""
}

## Outputs

output "private_ip" {
  value = aws_instance.example.private_ip
}

output "public_ip" {
  value = aws_instance.example.public_ip
}

output "ipv6_addresses" {
  value = aws_instance.example.ipv6_addresses
}


# Get the latest Amazon Linux 2 AMI matching the specified name pattern

data "aws_ami" "ami" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# look up VPC by tag:Name

data "aws_vpc" "vpc" {
  tags = {
    Name = "${var.vpc_short_name}-vpc"
  }
}

# look up Subnet (within the selected VPC, just in case several VPCs in your
# AWS account happen to have identically-named Subnets) by tag:Name

data "aws_subnet" "public1-a-net" {
  vpc_id = data.aws_vpc.vpc.id

  tags = {
    Name = "${var.vpc_short_name}-public1-a-net"
  }
}

# launch an EC2 instance in the selected Subnet

resource "aws_instance" "example" {
  tags = {
    Name = "example-instance"
  }

  ami                    = data.aws_ami.ami.id
  instance_type          = "t3.nano"
  subnet_id              = data.aws_subnet.public1-a-net.id
  vpc_security_group_ids = [aws_security_group.example.id]

  # use "null" to omit this argument if we didn't create an aws_key_pair
  key_name = length(aws_key_pair.example) > 0 ? aws_key_pair.example[0].key_name : null

  # assign IPv6 if available, even if assign_ipv6_address_on_creation is
  # disabled for the subnet
  ipv6_address_count = (data.aws_subnet.public1-a-net.ipv6_cidr_block == null ? null : 1)

  # optional cloud-init customization
  user_data_base64 = data.cloudinit_config.user_data.rendered
}

# SSH Key Pair

resource "aws_key_pair" "example" {
  # only create this resource if ssh_public_key is specified
  count = var.ssh_public_key != "" ? 1 : 0

  key_name_prefix = "example-"
  public_key      = var.ssh_public_key
}

# Security Group

resource "aws_security_group" "example" {
  name_prefix = "example-"
  vpc_id      = data.aws_vpc.vpc.id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "allow_outbound" {
  security_group_id = aws_security_group.example.id
  type              = "egress"
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
}

resource "aws_security_group_rule" "allow_ssh" {
  # only create this rule if we have at least one CIDR block
  count = length(var.ssh_ipv4_cidr_blocks) + length(var.ssh_ipv6_cidr_blocks) > 0 ? 1 : 0

  security_group_id = aws_security_group.example.id
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_blocks       = var.ssh_ipv4_cidr_blocks
  ipv6_cidr_blocks  = var.ssh_ipv6_cidr_blocks
}

# User Data

# base64 gzipped cloud-config
data "cloudinit_config" "user_data" {
  gzip          = true
  base64_encode = true

  part {
    content_type = "text/cloud-config"
    content = templatefile("${path.module}/cloud-config.yml", {
      welcome_message = "Welcome to ${data.aws_vpc.vpc.tags["Name"]}."
    })
  }
}
