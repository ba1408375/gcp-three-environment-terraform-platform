#######################################
# GCP state isolation
#######################################

terraform {
  # Keep earlier cloud-provider state files separate. Initialize this
  # configuration with `terraform init -reconfigure`; do not migrate old state.
  backend "local" {
    path = "gcp.tfstate"
  }
}
