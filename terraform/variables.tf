variable "project_id" {
  description = "ID do projeto GCP onde o cluster vai ser criado"
  type        = string
  # não tem default — tem que passar explicitamente
}

variable "region" {
  description = "Região GCP do cluster"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Zona GCP para o node pool"
  type        = string
  default     = "us-central1-a"
}

variable "cluster_name" {
  description = "Nome do cluster GKE"
  type        = string
  default     = "gke-harness-demo"
}

variable "kubernetes_version" {
  description = "Versão do Kubernetes — manter atualizado"
  type        = string
  default     = "1.29"
}

variable "node_machine_type" {
  description = "Tipo de máquina para os nodes"
  type        = string
  # e2-standard-2 é bom custo-benefício pra demos
  default     = "e2-standard-2"
}

variable "node_count_initial" {
  description = "Número inicial de nodes no pool"
  type        = number
  default     = 2
}

variable "node_count_min" {
  description = "Mínimo de nodes para o autoscaling"
  type        = number
  default     = 1
}

variable "node_count_max" {
  description = "Máximo de nodes para o autoscaling"
  type        = number
  default     = 5
}

variable "node_disk_size_gb" {
  description = "Tamanho do disco dos nodes em GB"
  type        = number
  default     = 50
}

variable "network_name" {
  description = "Nome da VPC onde o cluster vai ser criado"
  type        = string
  default     = "default"
}

variable "subnetwork_name" {
  description = "Nome da subnet para o cluster"
  type        = string
  default     = "default"
}

variable "harness_delegate_namespace" {
  description = "Namespace onde o delegate do Harness vai ser instalado"
  type        = string
  default     = "harness-delegate"
}

variable "environment" {
  description = "Ambiente (staging ou production)"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "ambiente deve ser 'staging' ou 'production'"
  }
}

variable "labels" {
  description = "Labels comuns aplicadas em todos os recursos"
  type        = map(string)
  default = {
    project    = "harness-platform-complete-demo"
    managed-by = "terraform"
    team       = "platform"
    owner      = "leandroninja"
  }
}
