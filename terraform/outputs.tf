output "cluster_name" {
  description = "Nome do cluster GKE criado"
  value       = google_container_cluster.harness_demo.name
}

output "cluster_endpoint" {
  description = "Endpoint do cluster GKE — necessário pra configurar o kubeconfig"
  value       = google_container_cluster.harness_demo.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Certificado CA do cluster — usado para autenticação"
  value       = google_container_cluster.harness_demo.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "cluster_location" {
  description = "Localização (região/zona) do cluster"
  value       = google_container_cluster.harness_demo.location
}

output "node_pool_name" {
  description = "Nome do node pool principal"
  value       = google_container_node_pool.harness_demo_nodes.name
}

output "kubeconfig_command" {
  description = "Comando pra configurar o kubectl apontando pro cluster"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.harness_demo.name} --region ${var.region} --project ${var.project_id}"
}

output "harness_delegate_install_hint" {
  description = "Dica de como instalar o delegate do Harness no cluster"
  value       = "kubectl apply -f harness/delegate/harness-delegate.yaml -n ${var.harness_delegate_namespace}"
}

output "project_id" {
  description = "ID do projeto GCP utilizado"
  value       = var.project_id
}
