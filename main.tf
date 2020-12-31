provider "google" {
  project = var.project
  region  = var.region
}

# Generate a random suffix for SQL instances, since there is a delay before you
# are allowed to reuse instance names.
resource "random_id" "sql" {
  prefix      = "spoke-sql"
  byte_length = "8"
}

resource "google_sql_database_instance" "spoke-sql" {
  name                = random_id.sql.hex
  region              = var.region
  database_version    = "POSTGRES_12"
  # Allow deletion during development.
  # TODO: Make this configurable so production instances cannot be deleted by
  # Terraform.
  deletion_protection = "false"

  settings {
    tier = "db-f1-micro"

    ip_configuration {
      ipv4_enabled = true
    }

    backup_configuration {
      enabled = false
    }
  }
}

resource "random_password" "sql-password" {
  length = 16
}

resource "google_sql_user" "spoke-sql-user" {
  name            = "sqluser"
  instance        = google_sql_database_instance.spoke-sql.name
  password        = random_password.sql-password.result
  deletion_policy = "ABANDON"
}

resource "google_sql_database" "spoke-db" {
  name     = "spoke-db"
  instance = google_sql_database_instance.spoke-sql.name
}

resource "google_project_service" "run-service" {
  service = "run.googleapis.com"
}

# TODO: see if there's a way to generate this as a sensitive value
resource "random_id" "session-secret" {
  byte_length = 20
}

resource "google_service_account" "spoke-sa" {
  account_id   = "spoke-sa"
  display_name = "Spoke Service Account"
}

data "google_iam_policy" "spoke-token-creator" {
  binding {
    role    = "roles/iam.serviceAccountTokenCreator"
    members = [
      "serviceAccount:${google_service_account.spoke-sa.email}",
    ]
  }
}

# The service account needs to sign URLs as itself for export.
resource "google_service_account_iam_policy" "spoke-sa-iam" {
  service_account_id = google_service_account.spoke-sa.name
  policy_data        = data.google_iam_policy.spoke-token-creator.policy_data
}

resource "google_project_iam_member" "sql-client" {
  role   = "roles/cloudsql.client"
  member = "serviceAccount:${google_service_account.spoke-sa.email}"
}

# GCS bucket names must be globally unique.
resource "random_uuid" "bucket-suffix" { }

# TODO: give user the option of specifying a pre-existing bucket or disabling
# export altogether.
resource "google_storage_bucket" "spoke-export" {
  name                        = "spoke-export-${random_uuid.bucket-suffix.result}"
  # Destroy all objects during testing.
  force_destroy               = true
  location                    = upper(var.region)
  uniform_bucket_level_access = true
}

# In production, google_storage_bucket_iam_policy might be better so we have no
# extra permissions hanging around.
resource "google_storage_bucket_iam_binding" "spoke-export-create" {
  bucket = google_storage_bucket.spoke-export.name
  role = "roles/storage.objectCreator"

  members = [
    "serviceAccount:${google_service_account.spoke-sa.email}"
  ]
}

resource "google_storage_bucket_iam_binding" "spoke-export-view" {
  bucket = google_storage_bucket.spoke-export.name
  role = "roles/storage.objectViewer"

  members = [
    "serviceAccount:${google_service_account.spoke-sa.email}"
  ]
}

resource "google_cloud_run_service" "spoke-server" {
  name                       = "spoke-server"
  location                   = var.region
  autogenerate_revision_name = true

  template {
    spec {
      service_account_name = google_service_account.spoke-sa.email

      containers {
        image = var.spoke_container
        env {
          name  = "JOBS_SAME_PROCESS"
          value = "1"
        }
        env {
          name  = "DB_TYPE"
          value = "pg"
        }
        env {
          name  = "DB_NAME"
          value = google_sql_database.spoke-db.name
        }
        env {
          name  = "DB_USER"
          value = google_sql_user.spoke-sql-user.name
        }
        env {
          name  = "DB_PASSWORD"
          value = google_sql_user.spoke-sql-user.password
        }
        env {
          name  = "SESSION_SECRET"
          value = random_id.session-secret.b64_std
        }
        env {
          name  = "DB_SOCKET_PATH"
          value = "/cloudsql"
        }
        env {
          name  = "CLOUD_SQL_CONNECTION_NAME"
          value = google_sql_database_instance.spoke-sql.connection_name
        }
        env {
          name  = "KNEX_MIGRATION_DIR"
          value = "/spoke/build/server/migrations/"
        }
        env {
          name  = "PASSPORT_STRATEGY"
          value = "local"
        }
        env {
          name  = "BASE_URL"
          value = "https://${var.custom_domain}"
        }
        env {
          name  = "GCP_ACCESS_AVAILABLE"
          value = "true"
        }
        env {
          name  = "GCP_STORAGE_BUCKET_NAME"
          value = google_storage_bucket.spoke-export.name
        }
      }
    }

    metadata {
      annotations = {
        "autoscaling.knative.dev/maxScale"      = "1000"
        "run.googleapis.com/cloudsql-instances" = google_sql_database_instance.spoke-sql.connection_name
        "run.googleapis.com/client-name"        = "terraform"
      }
    }
  }

  depends_on = [google_project_service.run-service]
}

resource "google_cloud_run_service_iam_member" "allUsers" {
  service  = google_cloud_run_service.spoke-server.name
  location = google_cloud_run_service.spoke-server.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_domain_mapping" "spoke-domain" {
  name     = var.custom_domain
  location = var.region

  spec {
    route_name = google_cloud_run_service.spoke-server.name
  }

  metadata {
    namespace = var.project
  }
}

# Required by spoke-server at runtime to connect to SQL instance
resource "google_project_service" "sql-admin-service" {
  service = "sqladmin.googleapis.com"
}

output "spoke_url" {
  value = google_cloud_run_service.spoke-server.status[0].url
}

output "domain_record" {
  value = google_cloud_run_domain_mapping.spoke-domain.status[0].resource_records[0]
}
