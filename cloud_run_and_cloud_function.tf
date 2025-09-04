# main.tf

# Configure the Google Cloud provider
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0" # Use a suitable version
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# ---------------------------------------------------------------------------------------------------------------------
# Input Variables
# ---------------------------------------------------------------------------------------------------------------------
variable "project_id" {
  description = "The GCP project ID where resources will be deployed."
  type        = string
}

variable "region" {
  description = "The GCP region for deploying Cloud Run and Cloud Function."
  type        = string
  default     = "us-central1" # You can change this to your preferred region
}

# Cloud Run Variables
variable "cloud_run_service_name" {
  description = "Name for the Cloud Run service."
  type        = string
  default     = "my-combined-cloud-run"
}

variable "cloud_run_image" {
  description = "Container image for Cloud Run (e.g., gcr.io/cloudrun/hello)."
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello" # A public hello-world image
}

# Cloud Function Variables
variable "cloud_function_name" {
  description = "Name for the Cloud Function (Gen 2)."
  type        = string
  default     = "my-combined-http-function"
}

variable "cloud_function_runtime" {
  description = "Runtime for the Cloud Function (e.g., python39, nodejs16)."
  type        = string
  default     = "python39" # Matches the example main.py
}

variable "cloud_function_entry_point" {
  description = "Entry point function name in the source code."
  type        = string
  default     = "main" # Matches the example main.py
}

variable "cloud_function_source_zip_file" {
  description = "Local path to the Cloud Function source zip file."
  type        = string
  default     = "source.zip" # This file must exist in the same directory as main.tf
}

# ---------------------------------------------------------------------------------------------------------------------
# Cloud Run Service Configuration
# ---------------------------------------------------------------------------------------------------------------------

# Create a service account for the Cloud Run service
resource "google_service_account" "cloud_run_sa" {
  account_id   = "${var.cloud_run_service_name}-sa"
  display_name = "Service Account for ${var.cloud_run_service_name} Cloud Run"
  project      = var.project_id
}

# Deploy a Cloud Run service (using v2 API for consistency with Cloud Functions Gen 2)
resource "google_cloud_run_v2_service" "main_cloud_run_service" {
  name     = var.cloud_run_service_name
  location = var.region
  project  = var.project_id

  template {
    containers {
      image = var.cloud_run_image
    }
    service_account = google_service_account.cloud_run_sa.email
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
}

# Allow unauthenticated invocations for the Cloud Run service
resource "google_cloud_run_v2_service_iam_member" "cloud_run_public_access" {
  location = google_cloud_run_v2_service.main_cloud_run_service.location
  name     = google_cloud_run_v2_service.main_cloud_run_service.name
  member   = "allUsers"
  role     = "roles/run.invoker"
}

# ---------------------------------------------------------------------------------------------------------------------
# Cloud Function (Generation 2) Configuration
# ---------------------------------------------------------------------------------------------------------------------

# Generate a unique suffix for the GCS bucket name
resource "random_id" "bucket_suffix" {
  byte_length = 8
}

# GCS bucket to store the Cloud Function's source code
resource "google_storage_bucket" "function_source_bucket" {
  name          = "${var.project_id}-${var.cloud_function_name}-source-${random_id.bucket_suffix.hex}"
  location      = var.region
  project       = var.project_id
  uniform_bucket_level_access = true
  # IMPORTANT: force_destroy = true will delete all objects in the bucket when `terraform destroy` is run.
  # Use with caution in production, but useful for examples.
  force_destroy = true
}

# Upload the Cloud Function source code (source.zip) to the GCS bucket
resource "google_storage_bucket_object" "function_source_zip" {
  name   = var.cloud_function_source_zip_file
  bucket = google_storage_bucket.function_source_bucket.name
  source = var.cloud_function_source_zip_file # Local path to your zip file
  content_type = "application/zip"
}

# Create a service account for the Cloud Function
resource "google_service_account" "cloud_function_sa" {
  account_id   = "${var.cloud_function_name}-sa"
  display_name = "Service Account for ${var.cloud_function_name} Cloud Function"
  project      = var.project_id
}

# Grant the Cloud Function service account necessary permissions
# The 'roles/run.invoker' is typically sufficient for Gen2 functions that have public access.
# If the function needs to access other GCP services, more specific roles should be added.
resource "google_project_iam_member" "cloud_function_sa_artifact_registry_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader" # Needed for Cloud Build which builds the function
  member  = "serviceAccount:${google_service_account.cloud_function_sa.email}"
}

resource "google_project_iam_member" "cloud_function_sa_logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter" # For the function to write logs
  member  = "serviceAccount:${google_service_account.cloud_function_sa.email}"
}

# Deploy the Cloud Function (Generation 2)
resource "google_cloudfunctions2_function" "main_cloud_function" {
  name        = var.cloud_function_name
  location    = var.region
  project     = var.project_id
  description = "An HTTP triggered Cloud Function (Gen 2)"

  build_config {
    runtime     = var.cloud_function_runtime
    entry_point = var.cloud_function_entry_point
    source {
      storage_source {
        bucket = google_storage_bucket.function_source_bucket.name
        object = google_storage_bucket_object.function_source_zip.name
      }
    }
  }

  service_config {
    available_memory_mb   = 128
    timeout_seconds       = 60
    service_account_email = google_service_account.cloud_function_sa.email
  }

  # For an HTTP-triggered Cloud Function (Gen 2), you typically don't
  # specify an event_trigger if it's purely HTTP. The public access is
  # handled by IAM on the underlying Cloud Run service.
}

# Allow unauthenticated invocations for the Cloud Function (Gen 2 uses Cloud Run internally)
resource "google_cloud_run_v2_service_iam_member" "cloud_function_public_access" {
  location = google_cloudfunctions2_function.main_cloud_function.location
  name     = google_cloudfunctions2_function.main_cloud_function.name
  member   = "allUsers"
  role     = "roles/run.invoker"
}


# ---------------------------------------------------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------------------------------------------------

output "cloud_run_service_url" {
  description = "The URL of the deployed Cloud Run service."
  value       = google_cloud_run_v2_service.main_cloud_run_service.uri
}

output "cloud_run_service_account_email" {
  description = "The email of the service account used by the Cloud Run service."
  value       = google_service_account.cloud_run_sa.email
}

output "cloud_function_url" {
  description = "The URL of the deployed Cloud Function."
  value       = google_cloudfunctions2_function.main_cloud_function.service_config[0].uri
}

output "cloud_function_service_account_email" {
  description = "The email of the service account used by the Cloud Function."
  value       = google_service_account.cloud_function_sa.email
}

output "cloud_function_source_bucket_name" {
  description = "The name of the GCS bucket storing the Cloud Function source code."
  value       = google_storage_bucket.function_source_bucket.name
}
