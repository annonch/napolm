provider "google" {
  project = "nomadic-code"
  region  = "us-central1"
  zone    = "us-central1-c"
}

provider "google-beta" {
  project     = "nomadic-code"
  region      = "us-central1"
  zone        = "us-central1-c"
}

terraform {
  backend "gcs" {
    bucket  = "nomadic-code-infra"
    prefix  = "terraform/emacs-cloudrun"
  }
}

# Define the service account
resource "google_service_account" "emacs" {
  account_id   = "emacs-sa"
  display_name = "Emacs Cloud Run Service Account"
  project = "nomadic-code"
}

# add permissions to invoke this cloud run
resource "google_cloud_run_service_iam_member" "emacs-invoker-chris" {
  service  = google_cloud_run_service.emacs.name
  location = google_cloud_run_service.emacs.location
  role     = "roles/run.invoker"
  member   = "user:annonch@gmail.com"
}
# add permissions to invoke this cloud run
#resource "google_cloud_run_service_iam_member" "emacs-invoker-allUsers" {
#  service  = google_cloud_run_service.emacs.name
#  location = google_cloud_run_service.emacs.location
#  role     = "roles/run.invoker"
#  member   = "allUsers"
#}

# Build and Push Docker Image to GCR
resource "null_resource" "build_push_image" {
  provisioner "local-exec" {
    command = <<EOT
      podman build -t "us-central1-docker.pkg.dev/nomadic-code/personal/emacs:${var.TAG}" .
      podman push "us-central1-docker.pkg.dev/nomadic-code/personal/emacs:${var.TAG}"
    EOT
  }
}
  

# Deploy to Cloud Run with service account
resource "google_cloud_run_service" "emacs" {
  provider = google-beta
  name     = "emacs"
  location = "us-central1"
  template {
    metadata {
      annotations = {
        "autoscaling.knative.dev/maxScale"  = "1"
	"autoscaling.knative.dev/minScale"  = "0"
	"startup_cpu_boost" = "true"
    	}	
      }
    spec {
      container_concurrency=80
      timeout_seconds=30
      service_account_name = google_service_account.emacs.email   
      containers {
	image = "us-central1-docker.pkg.dev/nomadic-code/personal/emacs:${var.TAG}"
	ports {
	  container_port = 4222
	}
	liveness_probe {
          http_get {
            path = "/health"
            port = 4222
          }
          initial_delay_seconds = 5
          period_seconds        = 5
        }

        startup_probe {
          http_get {
            path = "/health"
            port = 4222
          }
          initial_delay_seconds = 3
          period_seconds        = 5
        }
	resources {
	  limits = {
	    cpu = "1000m"
	    memory = "256Mi" 
	  }
	}
      }
    }
  }
  traffic {
    percent         = 100
    latest_revision = true
  }

  lifecycle {
    ignore_changes = [
      metadata.0.annotations,
    ]
  }
}

variable "TAG" {
  type = string
}

# Make the Cloud Run service public
resource "google_cloud_run_service_iam_member" "public_access" {
  service  = google_cloud_run_service.emacs.name
  location = google_cloud_run_service.emacs.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Output the Cloud Run URL
output "cloud_run_url" {
  value = google_cloud_run_service.emacs.status[0].url
}

