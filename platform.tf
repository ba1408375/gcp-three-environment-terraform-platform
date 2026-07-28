#######################################
# Added-service rendering
#######################################

locals {
  function_name = substr(
    "${var.project_name}-faas-${local.resource_suffix}",
    0,
    63
  )

  function_url = google_cloudfunctions2_function.faas.service_config[0].uri

  faas_build_roles = toset([
    "roles/artifactregistry.writer",
    "roles/logging.logWriter",
    "roles/storage.objectViewer"
  ])

  platform_compose = {
    for environment in keys(var.environment_instances) : environment => templatefile("${path.module}/platform/docker-compose.yml.tftpl", {
      images        = var.platform_images
      nifi_username = var.platform_nifi_username
      nifi_password = random_password.platform_nifi[environment].result
    })
  }

  platform_kong_config = templatefile("${path.module}/platform/kong.yml.tftpl", {
    faas_url = local.function_url
  })

  platform_user_data = {
    for environment in keys(var.environment_instances) : environment => templatefile("${path.module}/platform_userdata.sh", {
      ar_index         = file("${path.module}/platform/ar/index.html")
      vr_index         = file("${path.module}/platform/vr/index.html")
      kong_config      = local.platform_kong_config
      compose_config   = local.platform_compose[environment]
      environment_name = environment
    })
  }
}

resource "random_password" "platform_nifi" {
  for_each = var.environment_instances

  length      = 24
  special     = false
  min_lower   = 4
  min_upper   = 4
  min_numeric = 4
}

#######################################
# Cloud Run function source package
#######################################

resource "random_string" "gcp_resource_suffix" {
  length  = 8
  upper   = false
  special = false
}

data "archive_file" "faas" {
  type             = "zip"
  source_dir       = "${path.module}/faas"
  output_file_mode = "0666"
  output_path      = "${path.module}/faas/function_source.zip"
  excludes = [
    "function_source.zip",
    "function_app.zip",
    "lambda_function.zip",
    "__pycache__",
    ".pytest_cache"
  ]
}

resource "google_storage_bucket" "faas_source" {
  project                     = var.gcp_project_id
  name                        = "${var.project_name}-faas-src-${random_string.gcp_resource_suffix.result}"
  location                    = var.gcp_region
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true
  labels                      = local.common_labels

  versioning {
    enabled = false
  }

  soft_delete_policy {
    retention_duration_seconds = 0
  }

  depends_on = [
    google_project_service.required["storage.googleapis.com"]
  ]
}

resource "google_storage_bucket_object" "faas_source" {
  name         = "function-source-${data.archive_file.faas.output_md5}.zip"
  bucket       = google_storage_bucket.faas_source.name
  source       = data.archive_file.faas.output_path
  content_type = "application/zip"
}

#######################################
# Cloud Run function identity
#######################################

resource "google_service_account" "faas" {
  project      = var.gcp_project_id
  account_id   = substr("${var.project_name}-faas-${local.compact_suffix}", 0, 30)
  display_name = "DevCloud Cloud Run function"
  description  = "Runtime identity for the shared HTTP FaaS endpoint"

  depends_on = [
    google_project_service.required["iam.googleapis.com"]
  ]
}

resource "google_project_iam_member" "faas_logging" {
  project = var.gcp_project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.faas.email}"
}

resource "google_service_account" "faas_build" {
  project      = var.gcp_project_id
  account_id   = substr("${var.project_name}-build-${local.compact_suffix}", 0, 30)
  display_name = "DevCloud function build"
  description  = "Dedicated Cloud Build identity for packaging the shared FaaS endpoint"

  depends_on = [
    google_project_service.required["iam.googleapis.com"]
  ]
}

resource "google_project_iam_member" "faas_build" {
  for_each = local.faas_build_roles

  project = var.gcp_project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.faas_build.email}"
}

#######################################
# Cloud Run functions (2nd gen)
#######################################

resource "google_cloudfunctions2_function" "faas" {
  project     = var.gcp_project_id
  name        = local.function_name
  location    = var.gcp_region
  description = "Working Google Cloud native Function-as-a-Service endpoint"
  labels      = local.common_labels

  build_config {
    runtime         = var.function_python_runtime
    entry_point     = "faas"
    service_account = google_service_account.faas_build.name

    source {
      storage_source {
        bucket     = google_storage_bucket.faas_source.name
        object     = google_storage_bucket_object.faas_source.name
        generation = google_storage_bucket_object.faas_source.generation
      }
    }
  }

  service_config {
    available_memory                 = var.function_available_memory
    timeout_seconds                  = var.function_timeout_seconds
    min_instance_count               = 0
    max_instance_count               = var.function_max_instance_count
    max_instance_request_concurrency = 1
    ingress_settings                 = "ALLOW_ALL"
    all_traffic_on_latest_revision   = true
    service_account_email            = google_service_account.faas.email

    environment_variables = {
      CLOUD_PROVIDER = "gcp"
    }
  }

  depends_on = [
    google_project_service.required["artifactregistry.googleapis.com"],
    google_project_service.required["cloudbuild.googleapis.com"],
    google_project_service.required["cloudfunctions.googleapis.com"],
    google_project_service.required["run.googleapis.com"],
    google_project_iam_member.faas_build,
    google_project_iam_member.faas_logging
  ]
}

resource "google_cloud_run_service_iam_member" "faas_public" {
  count = var.function_allow_unauthenticated ? 1 : 0

  project  = var.gcp_project_id
  location = google_cloudfunctions2_function.faas.location
  service  = google_cloudfunctions2_function.faas.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
