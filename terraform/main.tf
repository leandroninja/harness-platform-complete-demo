terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }

  # backend comentado — descomentar quando tiver bucket GCS disponível
  # backend "gcs" {
  #   bucket = "tfstate-harness-demo-leandroninja"
  #   prefix = "terraform/state"
  # }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# habilita as APIs necessárias na GCP
resource "google_project_service" "container_api" {
  service            = "container.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "compute_api" {
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

# service account dedicada pro node pool — princípio de menor privilégio
resource "google_service_account" "gke_node_sa" {
  account_id   = "gke-node-sa-harness-demo"
  display_name = "GKE Node Service Account — harness-demo"
  description  = "SA usada pelos nodes do cluster para acessar recursos GCP"
}

# permissões mínimas necessárias pra nodes GKE
resource "google_project_iam_member" "gke_node_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gke_node_sa.email}"
}

resource "google_project_iam_member" "gke_node_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gke_node_sa.email}"
}

resource "google_project_iam_member" "gke_node_artifact_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.gke_node_sa.email}"
}

# cluster GKE principal
resource "google_container_cluster" "harness_demo" {
  name     = var.cluster_name
  location = var.region

  # remove o default node pool — vamos criar um customizado
  remove_default_node_pool = true
  initial_node_count       = 1

  # versão do kubernetes — usa o canal regular pra ter updates automáticos
  min_master_version = var.kubernetes_version

  network    = var.network_name
  subnetwork = var.subnetwork_name

  # workload identity — melhor prática de segurança no GKE
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # desabilita dashboard legado — CVE histórica
  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
    # network policy addon habilitado pra isolamento de pods
    network_policy_config {
      disabled = false
    }
  }

  network_policy {
    enabled  = true
    provider = "CALICO"
  }

  # logging e monitoring via Cloud Operations
  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  # evita acesso público direto ao control plane
  master_authorized_networks_config {
    cidr_blocks {
      # TODO: restringir pra IP do escritório/VPN em produção real
      cidr_block   = "0.0.0.0/0"
      display_name = "all — restringir em produção"
    }
  }

  # configura shielded nodes pra segurança adicional
  enable_shielded_nodes = true

  resource_labels = var.labels

  depends_on = [
    google_project_service.container_api,
    google_project_service.compute_api,
  ]

  lifecycle {
    # evita destruir o cluster se só mudar algumas configs
    ignore_changes = [
      initial_node_count,
    ]
  }
}

# node pool principal
resource "google_container_node_pool" "harness_demo_nodes" {
  name       = "harness-demo-main-pool"
  location   = var.region
  cluster    = google_container_cluster.harness_demo.name

  # autoscaling habilitado
  autoscaling {
    min_node_count = var.node_count_min
    max_node_count = var.node_count_max
  }

  initial_node_count = var.node_count_initial

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type = var.node_machine_type
    disk_size_gb = var.node_disk_size_gb
    disk_type    = "pd-ssd"

    service_account = google_service_account.gke_node_sa.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    # workload identity nos nodes
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    # shielded instance config
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    labels = merge(var.labels, {
      node-pool = "main"
    })

    tags = ["gke-harness-demo", "harness-delegate"]
  }
}
