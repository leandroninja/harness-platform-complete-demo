package pipeline.security

import future.keywords.if
import future.keywords.in

# =====================================================
# Políticas de segurança para gates do pipeline Harness
# Avaliadas pelo Harness Policy Engine antes de cada deploy
# =====================================================

# policy principal — nega se qualquer regra falhar
deny[msg] if {
    violation[msg]
}

# --- regra 1: bloquear imagens sem scan de vulnerabilidade ---
# toda imagem precisa ter passado pelo scan trivy antes do deploy
violation[msg] if {
    input.stage.type == "Deployment"
    artifact := input.stage.spec.service.serviceDefinition.spec.artifacts.primary
    not artifact_has_scan_result(artifact)
    msg := sprintf(
        "imagem '%v' não possui resultado de scan de vulnerabilidade. execute o pipeline STO antes do CD.",
        [artifact.spec.tag]
    )
}

artifact_has_scan_result(artifact) if {
    # verifica se existe metadado de scan no artifact
    artifact.metadata.scanStatus == "passed"
}

# --- regra 2: exigir labels obrigatórios nos deployments ---
required_labels := {
    "app",
    "version",
    "team",
    "app.kubernetes.io/managed-by"
}

violation[msg] if {
    input.stage.type == "Deployment"
    manifest := input.stage.spec.manifests[_]
    manifest.type == "K8sManifest"
    deployment := manifest.spec.store.content
    deployment.kind == "Deployment"

    existing_labels := {k | deployment.metadata.labels[k]}
    missing := required_labels - existing_labels
    count(missing) > 0

    msg := sprintf(
        "deployment '%v' está faltando os labels obrigatórios: %v",
        [deployment.metadata.name, missing]
    )
}

# --- regra 3: bloquear containers privilegiados ---
violation[msg] if {
    input.stage.type == "Deployment"
    manifest := input.stage.spec.manifests[_]
    container := manifest.spec.store.content.spec.template.spec.containers[_]
    container.securityContext.privileged == true
    msg := sprintf(
        "container '%v' está configurado como privileged — não permitido",
        [container.name]
    )
}

# também bloqueia se allowPrivilegeEscalation for true
violation[msg] if {
    input.stage.type == "Deployment"
    manifest := input.stage.spec.manifests[_]
    container := manifest.spec.store.content.spec.template.spec.containers[_]
    container.securityContext.allowPrivilegeEscalation == true
    msg := sprintf(
        "container '%v' tem allowPrivilegeEscalation=true — não permitido em produção",
        [container.name]
    )
}

# --- regra 4: verificar resource limits ---
# containers sem limits definidos podem causar problemas no cluster inteiro
violation[msg] if {
    input.stage.type == "Deployment"
    manifest := input.stage.spec.manifests[_]
    container := manifest.spec.store.content.spec.template.spec.containers[_]
    not container.resources.limits.cpu
    msg := sprintf(
        "container '%v' não possui cpu limit definido — obrigatório",
        [container.name]
    )
}

violation[msg] if {
    input.stage.type == "Deployment"
    manifest := input.stage.spec.manifests[_]
    container := manifest.spec.store.content.spec.template.spec.containers[_]
    not container.resources.limits.memory
    msg := sprintf(
        "container '%v' não possui memory limit definido — obrigatório",
        [container.name]
    )
}

# --- regra 5: bloquear deploy em produção sem approval ---
# essa regra garante que ninguém pula o approval gate
violation[msg] if {
    input.stage.type == "Deployment"
    input.stage.spec.environment.environmentRef == "production"
    not pipeline_has_approval_stage(input.pipeline)
    msg := "deploy em produção requer approval gate — adicione um stage de aprovação no pipeline"
}

pipeline_has_approval_stage(pipeline) if {
    stage := pipeline.stages[_]
    stage.type == "Approval"
}

# --- regra 6: verificar se imagem usa tag latest ---
# latest é ruim porque não é determinístico
violation[msg] if {
    input.stage.type == "Deployment"
    artifact := input.stage.spec.service.serviceDefinition.spec.artifacts.primary
    artifact.spec.tag == "latest"
    msg := "usar tag 'latest' não é permitido em produção — use uma tag específica com o commit SHA"
}

# --- helper: ambiente de produção ---
is_production if {
    input.stage.spec.environment.environmentRef == "production"
}
