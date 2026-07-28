#######################################
# Google Cloud project and naming
#######################################

variable "gcp_project_id" {
  description = "Existing Google Cloud project ID with billing enabled"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.gcp_project_id))
    error_message = "gcp_project_id must be a valid 6-30 character Google Cloud project ID."
  }
}

variable "gcp_region" {
  description = "Google Cloud region used by the network, addresses, and Cloud Run function"
  type        = string
  default     = "us-central1"

  validation {
    condition     = can(regex("^[a-z]+-[a-z0-9]+[0-9]$", var.gcp_region))
    error_message = "gcp_region must be a valid Google Cloud region such as us-central1."
  }
}

variable "project_name" {
  description = "Short lowercase name used in Google Cloud resource names"
  type        = string
  default     = "devcloud"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,19}$", var.project_name))
    error_message = "project_name must start with a lowercase letter and contain 3-20 lowercase letters, digits, or hyphens."
  }
}

variable "request_id" {
  description = "Unique request identifier used to distinguish this deployment"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{0,31}$", var.request_id))
    error_message = "request_id must be 1-32 letters, digits, underscores, or hyphens and start with a letter or digit."
  }
}

#######################################
# Dev, test, and production VM sizing
#######################################

variable "environment_instances" {
  description = "Exactly three Compute Engine environments and the capacity assigned to each complete service stack"

  type = map(object({
    machine_type      = string
    boot_disk_size_gb = number
    subnet_cidr       = string
    zone              = string
  }))

  default = {
    dev = {
      machine_type      = "n2-standard-8"
      boot_disk_size_gb = 150
      subnet_cidr       = "10.42.10.0/24"
      zone              = "us-central1-a"
    }
    test = {
      machine_type      = "n2-standard-8"
      boot_disk_size_gb = 150
      subnet_cidr       = "10.42.20.0/24"
      zone              = "us-central1-b"
    }
    production = {
      machine_type      = "n2-standard-16"
      boot_disk_size_gb = 300
      subnet_cidr       = "10.42.30.0/24"
      zone              = "us-central1-c"
    }
  }

  validation {
    condition     = toset(keys(var.environment_instances)) == toset(["dev", "test", "production"])
    error_message = "environment_instances must contain exactly dev, test, and production."
  }

  validation {
    condition = alltrue([
      for environment in values(var.environment_instances) :
      environment.boot_disk_size_gb >= 100
    ])
    error_message = "Each environment needs at least 100 GB for container images and persistent Docker volumes."
  }

  validation {
    condition = alltrue([
      for environment in values(var.environment_instances) :
      can(cidrnetmask(environment.subnet_cidr))
    ])
    error_message = "Each subnet_cidr must be a valid IPv4 CIDR."
  }

  validation {
    condition = (
      length(distinct([
        for environment in values(var.environment_instances) :
        environment.subnet_cidr
      ])) == length(var.environment_instances) &&
      alltrue([
        for environment in values(var.environment_instances) :
        startswith(environment.subnet_cidr, "10.42.") &&
        endswith(environment.subnet_cidr, "/24") &&
        split("/", environment.subnet_cidr)[0] == cidrhost(environment.subnet_cidr, 0)
      ])
    )
    error_message = "Each environment needs a unique 10.42.x.0/24 subnet inside the 10.42.0.0/16 VPC."
  }

  validation {
    condition = alltrue([
      for environment in values(var.environment_instances) :
      can(regex("^[a-z]+-[a-z0-9]+[0-9]-[a-z]$", environment.zone))
    ])
    error_message = "Every environment zone must be a valid Google Cloud zone such as us-central1-a."
  }

  validation {
    condition = alltrue([
      for environment in values(var.environment_instances) :
      length(trimspace(environment.machine_type)) > 0
    ])
    error_message = "Every environment must specify a Compute Engine machine type."
  }
}

variable "boot_disk_type" {
  description = "Persistent Disk type used for every boot disk"
  type        = string
  default     = "pd-balanced"

  validation {
    condition     = contains(["pd-standard", "pd-balanced", "pd-ssd"], var.boot_disk_type)
    error_message = "boot_disk_type must be pd-standard, pd-balanced, or pd-ssd."
  }
}

#######################################
# Network and administrative access
#######################################

variable "public_service_allowed_cidrs" {
  description = "Trusted CIDRs allowed to reach demonstration service ports; empty disables public service access"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.public_service_allowed_cidrs : can(cidrnetmask(cidr))])
    error_message = "public_service_allowed_cidrs must contain only valid IPv4 CIDRs."
  }
}

variable "admin_allowed_cidrs" {
  description = "Trusted CIDRs allowed to use direct SSH; empty disables direct internet SSH"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.admin_allowed_cidrs : can(cidrnetmask(cidr))])
    error_message = "admin_allowed_cidrs must contain only valid IPv4 CIDRs."
  }
}

variable "enable_iap_ssh" {
  description = "Allow SSH through Identity-Aware Proxy from Google's documented TCP-forwarding range"
  type        = bool
  default     = true
}

variable "iap_ssh_members" {
  description = "Optional IAM members granted IAP tunnel, Compute Viewer, OS Admin Login, and VM service-account use"
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for member in var.iap_ssh_members :
      can(regex("^(user|group|serviceAccount):.+$", member))
    ])
    error_message = "iap_ssh_members entries must use IAM member syntax such as user:name@example.com."
  }
}

#######################################
# Existing core service credentials
#######################################

variable "mysql_root_password" {
  description = "MySQL root password"
  type        = string
  sensitive   = true
}

variable "mysql_database" {
  description = "MySQL database"
  type        = string
}

variable "mysql_user" {
  description = "MySQL application user"
  type        = string
}

variable "mysql_password" {
  description = "MySQL application password"
  type        = string
  sensitive   = true
}

variable "mariadb_root_password" {
  description = "MariaDB root password"
  type        = string
  sensitive   = true
}

variable "mariadb_database" {
  description = "MariaDB database"
  type        = string
}

variable "mariadb_user" {
  description = "MariaDB application user"
  type        = string
}

variable "mariadb_password" {
  description = "MariaDB application password"
  type        = string
  sensitive   = true
}

variable "postgres_user" {
  description = "PostgreSQL user"
  type        = string
}

variable "postgres_password" {
  description = "PostgreSQL password"
  type        = string
  sensitive   = true
}

variable "postgres_database" {
  description = "PostgreSQL database"
  type        = string
}

variable "mongodb_user" {
  description = "MongoDB administrator user"
  type        = string
}

variable "mongodb_password" {
  description = "MongoDB administrator password"
  type        = string
  sensitive   = true
}

variable "jupyter_token" {
  description = "Jupyter Notebook access token"
  type        = string
  sensitive   = true
}

#######################################
# Added platform services
#######################################

variable "platform_nifi_username" {
  description = "Single-user administrator name for NiFi"
  type        = string
  default     = "admin"

  validation {
    condition     = length(var.platform_nifi_username) >= 4
    error_message = "platform_nifi_username must contain at least four characters."
  }
}

variable "platform_images" {
  description = "Pinned public images used by the six added Docker services"

  type = object({
    static_web = string
    tensorflow = string
    kong       = string
    nifi       = string
    mediamtx   = string
  })

  default = {
    static_web = "nginx:1.28.0-alpine"
    tensorflow = "tensorflow/serving:2.20.0"
    kong       = "kong/kong-gateway:3.10.0.2"
    nifi       = "apache/nifi:2.10.0"
    mediamtx   = "bluenviron/mediamtx:1.18.2"
  }
}

#######################################
# Cloud Run function
#######################################

variable "function_python_runtime" {
  description = "Cloud Run functions Python runtime identifier"
  type        = string
  default     = "python314"
}

variable "function_available_memory" {
  description = "Memory assigned to each function instance"
  type        = string
  default     = "256M"
}

variable "function_timeout_seconds" {
  description = "Maximum function request duration"
  type        = number
  default     = 10

  validation {
    condition     = var.function_timeout_seconds >= 1 && var.function_timeout_seconds <= 3600
    error_message = "function_timeout_seconds must be between 1 and 3600."
  }
}

variable "function_max_instance_count" {
  description = "Maximum autoscaled Cloud Run function instances"
  type        = number
  default     = 1

  validation {
    condition     = var.function_max_instance_count >= 1
    error_message = "function_max_instance_count must be at least 1."
  }
}

variable "function_allow_unauthenticated" {
  description = "Allow public invocation so Kong can call the demonstration FaaS endpoint without an identity token"
  type        = bool
  default     = true
}

variable "common_labels" {
  description = "Additional lowercase labels applied to supported Google Cloud resources"
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for key, value in var.common_labels :
      can(regex("^[a-z][a-z0-9_-]{0,62}$", key)) &&
      can(regex("^[a-z0-9_-]{0,63}$", value))
    ])
    error_message = "Google Cloud label keys and values must be lowercase and use only letters, digits, underscores, or hyphens."
  }
}
