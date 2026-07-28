#######################################
# VM identity and administrative access
#######################################

locals {
  platform_service_account_roles = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter"
  ])

  iap_admin_project_roles = toset([
    "roles/compute.osAdminLogin",
    "roles/compute.viewer",
    "roles/iap.tunnelResourceAccessor"
  ])

  iap_admin_project_bindings = {
    for binding in setproduct(var.iap_ssh_members, local.iap_admin_project_roles) :
    "${binding[0]}|${binding[1]}" => {
      member = binding[0]
      role   = binding[1]
    }
    if var.enable_iap_ssh
  }
}

resource "google_service_account" "platform" {
  project      = var.gcp_project_id
  account_id   = substr("${var.project_name}-vm-${local.compact_suffix}", 0, 30)
  display_name = "DevCloud Compute Engine runtime"
  description  = "Least-privilege identity used by the three container-host VMs"

  depends_on = [
    google_project_service.required["iam.googleapis.com"]
  ]
}

resource "google_project_iam_member" "platform" {
  for_each = local.platform_service_account_roles

  project = var.gcp_project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.platform.email}"
}

resource "google_project_iam_member" "iap_admin" {
  for_each = local.iap_admin_project_bindings

  project = var.gcp_project_id
  role    = each.value.role
  member  = each.value.member
}

resource "google_service_account_iam_member" "iap_admin_service_account_user" {
  for_each = var.enable_iap_ssh ? var.iap_ssh_members : toset([])

  service_account_id = google_service_account.platform.name
  role               = "roles/iam.serviceAccountUser"
  member             = each.value
}

#######################################
# Combined 36-container startup script
#######################################

locals {
  core_user_data = {
    for environment in keys(var.environment_instances) : environment => templatefile("${path.module}/userdata.sh", {
      environment_name      = environment
      mysql_root_password   = var.mysql_root_password
      mysql_database        = var.mysql_database
      mysql_user            = var.mysql_user
      mysql_password        = var.mysql_password
      mariadb_root_password = var.mariadb_root_password
      mariadb_database      = var.mariadb_database
      mariadb_user          = var.mariadb_user
      mariadb_password      = var.mariadb_password
      postgres_user         = var.postgres_user
      postgres_password     = var.postgres_password
      postgres_database     = var.postgres_database
      mongodb_user          = var.mongodb_user
      mongodb_password      = var.mongodb_password
      jupyter_token         = var.jupyter_token
      webxr_index           = file("${path.module}/webxr/index.html")
    })
  }

  environment_startup_script = {
    for environment in keys(var.environment_instances) : environment => join("\n\n", [
      local.core_user_data[environment],
      local.platform_user_data[environment]
    ])
  }
}

#######################################
# Dev, test, and production VMs
#######################################

resource "google_compute_instance" "environment" {
  for_each = var.environment_instances

  project                   = var.gcp_project_id
  name                      = substr("${var.project_name}-${each.key}-${local.resource_suffix}", 0, 63)
  zone                      = each.value.zone
  machine_type              = each.value.machine_type
  allow_stopping_for_update = true
  can_ip_forward            = false
  deletion_protection       = false

  tags = [local.network_tag]

  labels = merge(local.common_labels, {
    environment = each.key
    stack       = "devcloud-multi-environment"
  })

  boot_disk {
    auto_delete = true

    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
      size  = each.value.boot_disk_size_gb
      type  = var.boot_disk_type

      labels = merge(local.common_labels, {
        environment = each.key
      })
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.environment[each.key].id

    access_config {
      nat_ip       = google_compute_address.environment[each.key].address
      network_tier = "PREMIUM"
    }
  }

  metadata = {
    enable-oslogin         = "TRUE"
    block-project-ssh-keys = "TRUE"
  }

  metadata_startup_script = local.environment_startup_script[each.key]

  service_account {
    email  = google_service_account.platform.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
    preemptible         = false
  }

  lifecycle {
    precondition {
      condition     = startswith(each.value.zone, "${var.gcp_region}-")
      error_message = "The ${each.key} zone (${each.value.zone}) must belong to gcp_region (${var.gcp_region})."
    }
  }

  depends_on = [
    google_project_iam_member.platform,
    google_compute_firewall.internal
  ]
}
