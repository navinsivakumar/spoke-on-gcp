provider "google" {
  project = var.project
  region  = var.region
}

resource "google_sql_user" "spoke-db-user" {
  name = "sqluser"
  instance = google_sql_database_instance.spoke-db.name
  password = random_password.sql-password.result
  deletion_policy = "ABANDON"
}

resource "random_password" "sql-password" {
  length = 16
}

resource "google_sql_database_instance" "spoke-db" {
  name   = random_id.sql.hex
  region = var.region
  settings {
    tier = "db-f1-micro"

    ip_configuration {
      ipv4_enabled = true
    }

    backup_configuration {
      enabled = false
    }
  }

  database_version = "POSTGRES_12"

  # Allow deletion during development.
  # TODO: Make this configurable so production instances cannot be deleted by
  # Terraform.
  deletion_protection  = "false"
}

# Generate a random suffix for SQL instances, since there is a delay before you
# are allowed to reuse instance names.
resource "random_id" "sql" {
  prefix = "spoke-sql"
  byte_lengh = "8"
}
