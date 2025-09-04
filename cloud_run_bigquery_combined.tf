# cloud_run_bigquery_combined.tf

# Configure the Google Cloud provider
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0" # Use a suitable version
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
  description = "The GCP region for deploying Cloud Run and BigQuery dataset."
  type        = string
  default     = "us-central1" # You can change this to your preferred region
}

# Cloud Run Variables
variable "cloud_run_service_name" {
  description = "Name for the Cloud Run service."
  type        = string
  default     = "my-cr-bq-combo-run"
}

variable "cloud_run_image" {
  description = "Container image for Cloud Run (e.g., gcr.io/cloudrun/hello)."
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello" # A public hello-world image
}

# BigQuery Variables
variable "bigquery_dataset_name" {
  description = "Name for the BigQuery dataset."
  type        = string
  default     = "my_cr_bq_combo_dataset"
}

variable "bigquery_table_name" {
  description = "Name for the BigQuery table."
  type        = string
  default     = "my_cr_bq_combo_table"
}

variable "bigquery_table_schema" {
  description = "The JSON schema for the BigQuery table."
  type        = string
  default     = <<EOF
[
  {
    "name": "id",
    "type": "INTEGER",
    "mode": "REQUIRED",
    "description": "Unique identifier"
  },
  {
    "name": "value",
    "type": "STRING",
    "mode": "NULLABLE",
    "description": "A string value"
  },
  {
    "name": "timestamp",
    "type": "TIMESTAMP",
    "mode": "NULLABLE",
    "description": "Timestamp of record creation"
  }
]
EOF
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

# Deploy a Cloud Run service
resource "google_cloud_run_v2_service" "main_cloud_run_service" {
  name     = var.cloud_run_service_name
  location = var.region
  project  = var.project_id

  template {
    containers {
      image = var.cloud_run_image
    }
    service_account = google_service_account.cloud_run_sa.email
    # Configure request timeout if needed
    # timeout_seconds = 300
    # Add environment variables here
    # env {
    #   name  = "BIGQUERY_DATASET"
    #   value = google_bigquery_dataset.main_dataset.dataset_id
    # }
    # env {
    #   name  = "BIGQUERY_TABLE"
    #   value = google_bigquery_table.main_table.table_id
    # }
    # env {
    #   name  = "GCP_PROJECT_ID"
    #   value = var.project_id
    # }
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
# BigQuery Dataset and Table Configuration
# ---------------------------------------------------------------------------------------------------------------------

# Create a BigQuery dataset
resource "google_bigquery_dataset" "main_dataset" {
  dataset_id                  = var.bigquery_dataset_name
  project                     = var.project_id
  location                    = var.region # BigQuery location can be multi-region like 'US' or 'EU', or a single region.
  default_table_expiration_ms = 3600000 # 1 hour
  description                 = "BigQuery dataset for Cloud Run and BigQuery combined example."

  access {
    role          = "OWNER"
    user_by_email = "serviceAccount:${google_service_account.cloud_run_sa.email}"
  }
}

# Create a BigQuery table within the dataset
resource "google_bigquery_table" "main_table" {
  dataset_id = google_bigquery_dataset.main_dataset.dataset_id
  table_id   = var.bigquery_table_name
  project    = var.project_id
  schema     = var.bigquery_table_schema
  expiration_time = 0 # No expiration
  description     = "BigQuery table for Cloud Run and BigQuery combined example."
}

# If your Cloud Run service needs to write to BigQuery, it will need permissions
# This grant allows the Cloud Run service account to be a BigQuery Data Editor
resource "google_bigquery_dataset_iam_member" "cloud_run_bigquery_writer" {
  dataset_id = google_bigquery_dataset.main_dataset.dataset_id
  role       = "roles/bigquery.dataEditor" # Allows inserting/updating data in the dataset's tables
  member     = "serviceAccount:${google_service_account.cloud_run_sa.email}"
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

output "bigquery_dataset_id" {
  description = "The ID of the provisioned BigQuery dataset."
  value       = google_bigquery_dataset.main_dataset.dataset_id
}

output "bigquery_table_id" {
  description = "The full ID of the provisioned BigQuery table."
  value       = google_bigquery_table.main_table.id
}
