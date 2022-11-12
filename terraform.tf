terraform {
  required_version = ">=1.3.4"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">=4.39.0"
    }

    external = {
      source  = "hashicorp/external"
      version = ">=2.2.3"
    }

    random = {
      source  = "hashicorp/random"
      version = ">=3.4.3"
    }

    time = {
      source  = "hashicorp/time"
      version = ">=0.9.1"
    }
  }
}
