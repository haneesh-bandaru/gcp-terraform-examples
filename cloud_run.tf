# cloudrun.tf
# Provisions a Cloud Run service on GCP and an optional public IAM binding.

variable "project_id" {
  description = "The GCP project ID where Cloud Run service will be deployed"
  type        = string
}

variable "region" {
  description = "GCP region for Cloud Run (e.g., us-central1)"
  type        = string
  default     = "us-central1"
}

variable "service_name" {
  description = "Cloud Run service name"
  type        = string
}

variable "image" {
  description = "Container image URI (e.g., gcr.io/my-project/my-image:tag or eu.gcr.io/...)"
  type        = string
}

variable "port" {
  description = "Port the container listens on"
  type        = number
  default     = 8080
}

variable "memory" {
  description = "Memory for the Cloud Run container (e.g., 256Mi, 512Mi)"
  type        = string
  default     = "256Mi"
}

variable "allow_unauthenticated" {
  description = "If true, grants allUsers the Cloud Run invoker role to make the service public"
  type        = bool
  default     = false
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Enable required APIs (optional convenience)
resource "google_project_service" "cloudrun_api" {
  project = var.project_id
  service = "run.googleapis.com"
}

resource "google_project_service" "iam_api" {
  project = var.project_id
  service = "iam.googleapis.com"
}

# Cloud Run service
resource "google_cloud_run_service" "service" {
  name     = var.service_name
  location = var.region

  template {
    spec {
      containers {
        image = var.image
        ports {
          container_port = var.port
        }
        resources {
          limits = {
            memory = var.memory
          }
        }
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  # Optional: ensure service account is created implicitly if needed
  autogenerate_revision_name = true
}

# Allow unauthenticated (public) access if requested
resource "google_cloud_run_service_iam_member" "public_invoker" {
  count   = var.allow_unauthenticated ? 1 : 0
  location = var.region
  project  = var.project_id
  service  = google_cloud_run_service.service.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Output the service URL
output "cloud_run_url" {
  description = "URL of the deployed Cloud Run service"
  value       = google_cloud_run_service.service.status[0].url
}
