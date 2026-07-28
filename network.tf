#######################################
# Google Cloud naming, labels, and APIs
#######################################

locals {
  resource_suffix = substr(
    trim(lower(replace(var.request_id, "/[^0-9A-Za-z-]/", "-")), "-"),
    0,
    24
  )

  compact_suffix = substr(
    lower(replace(var.request_id, "/[^0-9A-Za-z]/", "")),
    0,
    12
  )

  common_labels = merge(var.common_labels, {
    managed_by = "terraform"
    project    = var.project_name
    request_id = local.compact_suffix
    cloud      = "gcp"
  })

  network_tag = substr(
    "${var.project_name}-platform-${local.resource_suffix}",
    0,
    63
  )

  public_tcp_ports = [
    "1883",
    "1935",
    "3000",
    "5678",
    "8000",
    "8080-8083",
    "8085",
    "8090-8093",
    "8501",
    "8554",
    "8889",
    "8891"
  ]

  private_tcp_ports = [
    "3306",
    "3307",
    "5432",
    "6379",
    "8443",
    "8545",
    "8888",
    "9000",
    "18083",
    "27017"
  ]

  public_udp_ports = [
    "8000-8001",
    "8189",
    "8890"
  ]

  required_apis = toset([
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "cloudfunctions.googleapis.com",
    "compute.googleapis.com",
    "iam.googleapis.com",
    "iap.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "oslogin.googleapis.com",
    "run.googleapis.com",
    "storage.googleapis.com"
  ])
}

resource "google_project_service" "required" {
  for_each = local.required_apis

  project                    = var.gcp_project_id
  service                    = each.value
  disable_dependent_services = false
  disable_on_destroy         = false
}

#######################################
# Custom VPC and environment subnets
#######################################

resource "google_compute_network" "main" {
  project                 = var.gcp_project_id
  name                    = "${var.project_name}-${local.resource_suffix}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  mtu                     = 1460

  depends_on = [
    google_project_service.required["compute.googleapis.com"]
  ]
}

resource "google_compute_subnetwork" "environment" {
  for_each = var.environment_instances

  project                  = var.gcp_project_id
  name                     = "${var.project_name}-${each.key}-${local.resource_suffix}"
  region                   = var.gcp_region
  network                  = google_compute_network.main.id
  ip_cidr_range            = each.value.subnet_cidr
  private_ip_google_access = true
  stack_type               = "IPV4_ONLY"
}

#######################################
# Reserved external IPv4 addresses
#######################################

resource "google_compute_address" "environment" {
  for_each = var.environment_instances

  project      = var.gcp_project_id
  name         = "${var.project_name}-${each.key}-${local.resource_suffix}-ip"
  region       = var.gcp_region
  address_type = "EXTERNAL"
  network_tier = "PREMIUM"

  depends_on = [
    google_project_service.required["compute.googleapis.com"]
  ]
}

#######################################
# VPC firewall rules
#######################################

resource "google_compute_firewall" "internal" {
  project     = var.gcp_project_id
  name        = "${var.project_name}-${local.resource_suffix}-internal"
  description = "Allow platform traffic between the three environment subnets"
  network     = google_compute_network.main.name
  direction   = "INGRESS"
  priority    = 1200

  source_ranges = ["10.42.0.0/16"]
  target_tags   = [local.network_tag]

  allow {
    protocol = "tcp"
    ports    = concat(local.public_tcp_ports, local.private_tcp_ports)
  }

  allow {
    protocol = "udp"
    ports    = local.public_udp_ports
  }

  allow {
    protocol = "icmp"
  }
}

resource "google_compute_firewall" "public_tcp" {
  count = length(var.public_service_allowed_cidrs) > 0 ? 1 : 0

  project     = var.gcp_project_id
  name        = "${var.project_name}-${local.resource_suffix}-public-tcp"
  description = "Allow demonstration TCP services only from explicitly trusted CIDRs"
  network     = google_compute_network.main.name
  direction   = "INGRESS"
  priority    = 1100

  source_ranges = var.public_service_allowed_cidrs
  target_tags   = [local.network_tag]

  allow {
    protocol = "tcp"
    ports    = local.public_tcp_ports
  }
}

resource "google_compute_firewall" "public_udp" {
  count = length(var.public_service_allowed_cidrs) > 0 ? 1 : 0

  project     = var.gcp_project_id
  name        = "${var.project_name}-${local.resource_suffix}-public-udp"
  description = "Allow MediaMTX UDP services only from explicitly trusted CIDRs"
  network     = google_compute_network.main.name
  direction   = "INGRESS"
  priority    = 1110

  source_ranges = var.public_service_allowed_cidrs
  target_tags   = [local.network_tag]

  allow {
    protocol = "udp"
    ports    = local.public_udp_ports
  }
}

resource "google_compute_firewall" "iap_ssh" {
  count = var.enable_iap_ssh ? 1 : 0

  project     = var.gcp_project_id
  name        = "${var.project_name}-${local.resource_suffix}-iap-ssh"
  description = "Allow SSH only through Google Identity-Aware Proxy"
  network     = google_compute_network.main.name
  direction   = "INGRESS"
  priority    = 900

  source_ranges = ["35.235.240.0/20"]
  target_tags   = [local.network_tag]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "direct_ssh" {
  count = length(var.admin_allowed_cidrs) > 0 ? 1 : 0

  project     = var.gcp_project_id
  name        = "${var.project_name}-${local.resource_suffix}-direct-ssh"
  description = "Optional direct SSH from explicitly trusted administrator CIDRs"
  network     = google_compute_network.main.name
  direction   = "INGRESS"
  priority    = 910

  source_ranges = var.admin_allowed_cidrs
  target_tags   = [local.network_tag]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}
