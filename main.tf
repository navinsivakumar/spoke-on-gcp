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

resource "google_cloud_run_service" "spoke-server" {
  name                       = "spoke-server"
  location                   = var.region
  autogenerate_revision_name = true

  template {
    spec {
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
