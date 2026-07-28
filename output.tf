locals {
  environment_service_urls = {
    for environment, address in google_compute_address.environment : environment => {
      open_webui            = "http://${address.address}:3000"
      n8n                   = "http://${address.address}:5678"
      nginx                 = "http://${address.address}:8080"
      apache_httpd          = "http://${address.address}:8081"
      tomcat                = "http://${address.address}:8082"
      wildfly               = "http://${address.address}:8083"
      remix                 = "http://${address.address}:8085"
      webxr                 = "http://${address.address}:8090"
      pocketbase            = "http://${address.address}:8091"
      emqx_mqtt             = "mqtt://${address.address}:1883"
      ar                    = "http://${address.address}:8092"
      vr                    = "http://${address.address}:8093"
      api_management        = "http://${address.address}:8000"
      api_management_ar     = "http://${address.address}:8000/ar"
      api_management_vr     = "http://${address.address}:8000/vr"
      api_management_ai     = "http://${address.address}:8000/ai"
      api_management_video  = "http://${address.address}:8000/video"
      api_management_faas   = "http://${address.address}:8000/faas"
      tensorflow_model      = "http://${address.address}:8501/v1/models/half_plus_two"
      mediamtx_hls          = "http://${address.address}:8891/live/index.m3u8"
      mediamtx_webrtc       = "http://${address.address}:8889/live"
      mediamtx_rtsp_example = "rtsp://${address.address}:8554/live"
      mediamtx_rtmp_example = "rtmp://${address.address}:1935/live"
      faas                  = local.function_url
    }
  }

  environment_iap_ssh_commands = {
    for environment, instance in google_compute_instance.environment : environment =>
    "gcloud compute ssh ${instance.name} --project=${var.gcp_project_id} --zone=${instance.zone} --tunnel-through-iap"
    if var.enable_iap_ssh
  }

  environment_run_commands = {
    for environment, instance in google_compute_instance.environment : environment =>
    "gcloud compute ssh ${instance.name} --project=${var.gcp_project_id} --zone=${instance.zone} --tunnel-through-iap --command=\"sudo docker ps\""
    if var.enable_iap_ssh
  }

  environment_nifi_iap_tunnels = {
    for environment, instance in google_compute_instance.environment : environment =>
    "gcloud compute ssh ${instance.name} --project=${var.gcp_project_id} --zone=${instance.zone} --tunnel-through-iap -- -L 8443:127.0.0.1:8443"
    if var.enable_iap_ssh
  }
}

#######################################
# Google Cloud environment outputs
#######################################

output "gcp_project_id" {
  description = "Google Cloud project hosting the deployment"
  value       = var.gcp_project_id
}

output "network_name" {
  description = "Custom VPC network shared by the three environments"
  value       = google_compute_network.main.name
}

output "environment_instance_ids" {
  description = "Compute Engine instance IDs keyed by environment"
  value = {
    for environment, instance in google_compute_instance.environment :
    environment => instance.id
  }
}

output "environment_public_ips" {
  description = "Reserved external IPv4 addresses keyed by environment"
  value = {
    for environment, address in google_compute_address.environment :
    environment => address.address
  }
}

output "environment_private_ips" {
  description = "Private VPC addresses keyed by environment"
  value = {
    for environment, instance in google_compute_instance.environment :
    environment => instance.network_interface[0].network_ip
  }
}

output "environment_capacities" {
  description = "Configured machine type, boot disk, subnet, and zone for each environment"
  value = {
    for environment, settings in var.environment_instances : environment => {
      machine_type      = settings.machine_type
      boot_disk_size_gb = settings.boot_disk_size_gb
      boot_disk_type    = var.boot_disk_type
      subnet_cidr       = settings.subnet_cidr
      zone              = settings.zone
    }
  }
}

output "environment_service_urls" {
  description = "Service endpoints keyed by dev, test, and production"
  value       = local.environment_service_urls
}

output "environment_iap_ssh_commands" {
  description = "Identity-Aware Proxy SSH commands keyed by environment"
  value       = local.environment_iap_ssh_commands
}

output "environment_run_commands" {
  description = "IAP commands that verify running Docker containers"
  value       = local.environment_run_commands
}

output "environment_nifi_iap_tunnels" {
  description = "IAP SSH port-forwarding commands for the private NiFi UI"
  value       = local.environment_nifi_iap_tunnels
}

output "gcp_function_url" {
  description = "Shared Cloud Run function FaaS endpoint"
  value       = local.function_url
}

output "platform_vm_service_account" {
  description = "Service account attached to all three Compute Engine VMs"
  value       = google_service_account.platform.email
}

output "function_service_accounts" {
  description = "Dedicated runtime and build identities used by the Cloud Run function"
  value = {
    runtime = google_service_account.faas.email
    build   = google_service_account.faas_build.email
  }
}

#######################################
# NiFi access
#######################################

output "platform_nifi_username" {
  description = "NiFi single-user login name"
  value       = var.platform_nifi_username
}

output "environment_nifi_passwords" {
  description = "Generated NiFi passwords keyed by environment"
  value = {
    for environment, password in random_password.platform_nifi :
    environment => password.result
  }
  sensitive = true
}

#######################################
# Compatibility aliases
#######################################

output "public_ip" {
  description = "Development VM public IP retained as a compatibility alias"
  value       = google_compute_address.environment["dev"].address
}

output "instance_id" {
  description = "Development Compute Engine instance ID retained as a compatibility alias"
  value       = google_compute_instance.environment["dev"].id
}

output "platform_instance_id" {
  description = "Production Compute Engine instance ID retained as a compatibility alias"
  value       = google_compute_instance.environment["production"].id
}

output "platform_public_ip" {
  description = "Production external IP retained as a compatibility alias"
  value       = google_compute_address.environment["production"].address
}

output "platform_service_urls" {
  description = "Production service URLs retained as a compatibility alias"
  value       = local.environment_service_urls["production"]
}

output "platform_nifi_password" {
  description = "Production NiFi password retained as a compatibility alias"
  value       = random_password.platform_nifi["production"].result
  sensitive   = true
}

output "platform_nifi_iap_tunnel" {
  description = "Production NiFi IAP tunnel retained as a compatibility alias"
  value       = local.environment_nifi_iap_tunnels["production"]
}
