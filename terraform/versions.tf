terraform {
  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = ">= 2.17"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = ">= 2.13"
    }
  }
  required_version = ">= 0.13"
}
