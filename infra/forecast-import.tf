# Separate identity: the API/worker runtime must not read an issue-writing token.
resource "google_service_account" "forecast_import" {
  account_id   = "${var.name_prefix}-forecast"
  display_name = "Farmable forecast importer"
}

resource "google_project_iam_member" "forecast_cloudsql" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.forecast_import.email}"
}

resource "google_secret_manager_secret_iam_member" "forecast_database" {
  secret_id = google_secret_manager_secret.runtime["database-url"].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.forecast_import.email}"
}

resource "google_secret_manager_secret" "forecast_github" {
  secret_id = "${var.name_prefix}-forecast-github-token"
  replication {
    auto {}
  }
  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret_iam_member" "forecast_github" {
  secret_id = google_secret_manager_secret.forecast_github.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.forecast_import.email}"
}

resource "google_service_account_iam_member" "deployer_runs_as_forecast" {
  service_account_id = google_service_account.forecast_import.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.deployer.email}"
}

output "forecast_import_service_account" {
  value = google_service_account.forecast_import.email
}

output "forecast_github_token_secret" {
  value = google_secret_manager_secret.forecast_github.id
}
