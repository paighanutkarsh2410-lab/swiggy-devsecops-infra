variable "region" {
  description = "AWS region to deploy into. Must match the region in iam-policy.json."
  type        = string
  default     = "ap-southeast-1"
}

variable "instance_type" {
  description = "EC2 instance type for the K3s server. Check your free plan before changing it."
  type        = string
  default     = "t3.small"
}

variable "admin_cidr" {
  description = "Your public IP address in CIDR form, for example 203.0.113.10/32. Only this address can use SSH and the Kubernetes API."
  type        = string

  validation {
    condition     = can(cidrhost(var.admin_cidr, 0)) && !contains(["0.0.0.0/0", "::/0"], var.admin_cidr)
    error_message = "admin_cidr must be a valid CIDR and must not be open to the whole internet."
  }
}

variable "ssh_public_key" {
  description = "Contents of the SSH public key used to log in as ec2-user."
  type        = string
}

variable "vpc_cidr" {
  description = "Address range for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidr" {
  description = "Address range for the public subnet."
  type        = string
  default     = "10.20.1.0/24"
}

variable "root_volume_size_gb" {
  description = "Size of the server's root disk in GB."
  type        = number
  default     = 20
}
