variable "nat_ami_id" {
  description = "AMI used by the tim-lab NAT instance"
  type        = string
  default     = "ami-008deafd6f62cdfc8"
}

variable "enable_eks" {
  description = "Whether the tim-lab EKS cluster should exist"
  type        = bool
  default     = true
}
