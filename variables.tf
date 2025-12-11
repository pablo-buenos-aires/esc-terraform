variable "t3" {
  type        = string
  default     = "t3.micro"
}

variable "iam_user" {
  type        = string
  default     = "pablo"
}

required_providers {
  aws = {  source   = "hashicorp/aws",  version = "~> 6.15"  }
  random = { source = "hashicorp/random", version = "~> 3.6" }
}