terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "6.27.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}

provider "aws" {
  region = "us-east-1"
  alias = "us-east-1"
}