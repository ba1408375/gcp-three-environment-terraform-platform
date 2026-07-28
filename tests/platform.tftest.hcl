mock_provider "google" {
  mock_resource "google_service_account" {
    defaults = {
      id    = "projects/mock-project/serviceAccounts/mock-service-account@mock-project.iam.gserviceaccount.com"
      email = "mock-service-account@mock-project.iam.gserviceaccount.com"
      name  = "projects/mock-project/serviceAccounts/mock-service-account@mock-project.iam.gserviceaccount.com"
    }
  }

  mock_resource "google_compute_network" {
    defaults = {
      id = "projects/mock-project/global/networks/mock-vpc"
    }
  }

  mock_resource "google_compute_subnetwork" {
    defaults = {
      id = "projects/mock-project/regions/us-central1/subnetworks/mock-subnet"
    }
  }

  mock_resource "google_compute_address" {
    defaults = {
      address = "203.0.113.10"
    }
  }

  mock_resource "google_compute_instance" {
    defaults = {
      id = "projects/mock-project/zones/us-central1-a/instances/mock-vm"
      network_interface = {
        network_ip = "10.42.10.10"
      }
    }
  }

  mock_resource "google_cloudfunctions2_function" {
    defaults = {
      service_config = {
        uri = "https://devcloud-faas.example.run.app"
      }
    }
  }

  mock_resource "google_storage_bucket_object" {
    defaults = {
      generation = 1
    }
  }
}

mock_provider "archive" {
  mock_data "archive_file" {
    defaults = {
      output_md5          = "0123456789abcdef0123456789abcdef"
      output_base64sha256 = "bW9jay1hcmNoaXZlLWhhc2g="
    }
  }
}

mock_provider "random" {
  mock_resource "random_password" {
    defaults = {
      result = "MockNiFiPassword123456789"
    }
  }

  mock_resource "random_string" {
    defaults = {
      result = "mock1234"
    }
  }
}

run "three_environment_gcp_mock_apply" {
  command = apply

  variables {
    gcp_project_id = "mock-project-123456"
    request_id     = "validation"

    mysql_root_password = "ValidationRoot123"
    mysql_database      = "validation"
    mysql_user          = "validation"
    mysql_password      = "ValidationUser123"

    mariadb_root_password = "ValidationRoot123"
    mariadb_database      = "validation"
    mariadb_user          = "validation"
    mariadb_password      = "ValidationUser123"

    postgres_user     = "validation"
    postgres_password = "ValidationUser123"
    postgres_database = "validation"

    mongodb_user     = "validation"
    mongodb_password = "ValidationUser123"
    jupyter_token    = "ValidationToken123"
  }

  assert {
    condition = (
      toset(keys(google_compute_instance.environment)) == toset(["dev", "test", "production"]) &&
      toset(keys(google_compute_subnetwork.environment)) == toset(["dev", "test", "production"]) &&
      toset(keys(google_compute_address.environment)) == toset(["dev", "test", "production"])
    )
    error_message = "Terraform must create one VM, subnet, and reserved IP for dev, test, and production."
  }

  assert {
    condition = (
      google_compute_instance.environment["dev"].machine_type == "n2-standard-8" &&
      google_compute_instance.environment["test"].machine_type == "n2-standard-8" &&
      google_compute_instance.environment["production"].machine_type == "n2-standard-16"
    )
    error_message = "The three GCP environments must retain the required 32-vCPU and 128-GB-RAM capacity."
  }

  assert {
    condition = alltrue([
      for environment, instance in google_compute_instance.environment :
      startswith(instance.name, "devcloud-${environment}-validation") &&
      instance.labels.environment == environment &&
      contains(instance.tags, local.network_tag)
    ])
    error_message = "Every Compute Engine VM must be uniquely named and labelled for its environment."
  }

  assert {
    condition = (
      google_compute_instance.environment["dev"].boot_disk[0].initialize_params[0].size == 150 &&
      google_compute_instance.environment["test"].boot_disk[0].initialize_params[0].size == 150 &&
      google_compute_instance.environment["production"].boot_disk[0].initialize_params[0].size == 300 &&
      alltrue([
        for instance in values(google_compute_instance.environment) :
        instance.boot_disk[0].auto_delete &&
        instance.boot_disk[0].initialize_params[0].type == "pd-balanced"
      ])
    )
    error_message = "The environments must provide 600 GB of balanced Persistent Disk capacity in total."
  }

  assert {
    condition = alltrue([
      for instance in values(google_compute_instance.environment) :
      instance.metadata["enable-oslogin"] == "TRUE" &&
      instance.metadata["block-project-ssh-keys"] == "TRUE" &&
      instance.shielded_instance_config[0].enable_secure_boot &&
      instance.shielded_instance_config[0].enable_vtpm &&
      instance.shielded_instance_config[0].enable_integrity_monitoring
    ])
    error_message = "Every VM must use OS Login, block project keys, and enable all Shielded VM protections."
  }

  assert {
    condition = alltrue([
      for payload in values(nonsensitive(local.environment_startup_script)) :
      length(payload) <= 262144 &&
      length(regexall("container_name:", payload)) == 36 &&
      !strcontains(lower(payload), "amazon-ssm") &&
      strcontains(payload, "https://devcloud-faas.example.run.app")
    ])
    error_message = "Each GCP startup script must stay below 256 KB, contain all 36 containers, target the GCP function, and contain no AWS agent."
  }

  assert {
    condition = (
      length(google_compute_firewall.iap_ssh) == 1 &&
      length(google_compute_firewall.direct_ssh) == 0
    )
    error_message = "IAP SSH must be enabled and direct SSH disabled by default."
  }

  assert {
    condition = (
      toset(google_compute_firewall.iap_ssh[0].source_ranges) == toset(["35.235.240.0/20"]) &&
      anytrue([
        for rule in google_compute_firewall.iap_ssh[0].allow :
        rule.protocol == "tcp" && toset(rule.ports) == toset(["22"])
      ])
    )
    error_message = "The IAP firewall must allow only TCP port 22 from Google's documented range."
  }

  assert {
    condition = (
      length(google_compute_firewall.public_tcp) == 0 &&
      length(google_compute_firewall.public_udp) == 0 &&
      alltrue([
        for port in local.private_tcp_ports :
        !contains(local.public_tcp_ports, port)
      ])
    )
    error_message = "Public services must be disabled by default and data or administration ports must stay private."
  }

  assert {
    condition     = length(random_password.platform_nifi) == 3
    error_message = "NiFi must have a separate generated password in each GCP environment."
  }

  assert {
    condition = (
      google_cloudfunctions2_function.faas.build_config[0].runtime == "python314" &&
      google_cloudfunctions2_function.faas.build_config[0].entry_point == "faas" &&
      google_cloudfunctions2_function.faas.build_config[0].service_account == google_service_account.faas_build.name &&
      google_cloudfunctions2_function.faas.service_config[0].available_memory == "256M" &&
      google_cloudfunctions2_function.faas.service_config[0].timeout_seconds == 10 &&
      google_cloudfunctions2_function.faas.service_config[0].min_instance_count == 0 &&
      google_cloudfunctions2_function.faas.service_config[0].max_instance_count == 1 &&
      google_cloudfunctions2_function.faas.service_config[0].max_instance_request_concurrency == 1
    )
    error_message = "The shared FaaS endpoint must use the expected Python runtime and bounded Cloud Run capacity."
  }

  assert {
    condition = (
      google_storage_bucket.faas_source.uniform_bucket_level_access &&
      google_storage_bucket.faas_source.public_access_prevention == "enforced" &&
      length(google_cloud_run_service_iam_member.faas_public) == 1 &&
      google_cloud_run_service_iam_member.faas_public[0].member == "allUsers"
    )
    error_message = "Function source must remain private while the demonstration endpoint remains invokable by Kong."
  }

  assert {
    condition = (
      toset(keys(local.environment_service_urls)) == toset(["dev", "test", "production"]) &&
      toset(keys(local.environment_iap_ssh_commands)) == toset(["dev", "test", "production"]) &&
      toset(keys(local.environment_nifi_iap_tunnels)) == toset(["dev", "test", "production"])
    )
    error_message = "All environment outputs must contain exactly dev, test, and production."
  }
}
