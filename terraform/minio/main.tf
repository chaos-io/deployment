terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.1"
    }
  }
}

provider "docker" {
  host = "unix:///var/run/docker.sock"

  registry_auth {
    address     = "harbor.xxx"
    config_file = pathexpand("~/.docker/config.json")
  }
}

resource "docker_image" "minio" {
  name         = "minio/minio:latest"
  keep_locally = true
}

resource "docker_container" "my-minio" {
  image   = docker_image.minio.image_id
  name    = var.container_name
  env     = ["MINIO_ACCESS_KEY=minioadmin", "MINIO_SECRET_KEY=minioadmin"]
  command = ["server", "/data", "--console-address", ":40121", "-address", ":9000"]
  ports {
    internal = 9000
    external = 9000
  }
  ports {
    internal = 40121
    external = 40121
  }
  volumes {
    host_path      = "/opt/my-minio/data"
    container_path = "/data"
  }
  volumes {
    host_path      = "/opt/my-minio/config"
    container_path = "/config"
  }
}



