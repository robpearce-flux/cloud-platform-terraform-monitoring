# Prometheus proxy

data "template_file" "prometheus_proxy" {
  template = file("${path.module}/templates/oauth2-proxy.yaml.tpl")

  vars = {
    upstream = "http://prometheus-operator-kube-p-prometheus:9090"
    hostname = format(
      "%s.%s",
      "prometheus",
      var.cluster_domain_name,
    )
    exclude_paths        = "^/-/healthy$"
    issuer_url           = var.oidc_issuer_url
    client_id            = var.oidc_components_client_id
    client_secret        = var.oidc_components_client_secret
    cookie_secret        = random_id.session_secret.b64_std
    clusterName          = terraform.workspace
    ingress_redirect     = terraform.workspace == local.live_workspace ? true : false
    live_domain_hostname = "prometheus.${local.live_domain}"
  }
}

resource "helm_release" "prometheus_proxy" {
  name       = "prometheus-proxy"
  namespace  = kubernetes_namespace.monitoring.id
  repository = "https://oauth2-proxy.github.io/manifests"
  chart      = "oauth2-proxy"
  version    = "6.2.1"

  values = [
    data.template_file.prometheus_proxy.rendered,
  ]

  depends_on = [
    random_id.session_secret
  ]

  lifecycle {
    ignore_changes = [keyring]
  }
}

# Alertmanager proxy

data "template_file" "alertmanager_proxy" {
  template = file("${path.module}/templates/oauth2-proxy.yaml.tpl")

  vars = {
    upstream = "http://prometheus-operator-kube-p-alertmanager:9093"
    hostname = format(
      "%s.%s",
      "alertmanager",
      var.cluster_domain_name,
    )
    exclude_paths        = "^/-/healthy$"
    issuer_url           = var.oidc_issuer_url
    client_id            = var.oidc_components_client_id
    client_secret        = var.oidc_components_client_secret
    cookie_secret        = random_id.session_secret.b64_std
    clusterName          = terraform.workspace
    ingress_redirect     = local.ingress_redirect
    live_domain_hostname = "alertmanager.${local.live_domain}"
  }
}

resource "helm_release" "alertmanager_proxy" {
  name       = "alertmanager-proxy"
  namespace  = "monitoring"
  repository = "https://oauth2-proxy.github.io/manifests"
  chart      = "oauth2-proxy"
  version    = "6.2.1"

  values = [
    data.template_file.alertmanager_proxy.rendered,
  ]

  depends_on = [
    random_id.session_secret
  ]

  lifecycle {
    ignore_changes = [keyring]
  }
}

# Kibana_audit

data "template_file" "kibana_audit_proxy" {
  template = file("${path.module}/templates/oauth2-proxy.yaml.tpl")

  vars = {
    upstream = var.kibana_audit_upstream
    hostname = terraform.workspace == local.live_workspace ? format("%s.%s", "kibana-audit", local.live_domain) : format(
      "%s.%s",
      "kibana-audit",
      var.cluster_domain_name,
    )
    exclude_paths    = "^/-/healthy$"
    issuer_url       = var.oidc_issuer_url
    client_id        = var.oidc_components_client_id
    client_secret    = var.oidc_components_client_secret
    cookie_secret    = random_id.session_secret.b64_std
    ingress_redirect = false
    clusterName      = terraform.workspace
  }
}

resource "helm_release" "kibana_audit_proxy" {
  count      = var.enable_kibana_audit_proxy ? 1 : 0
  name       = "kibana-audit-proxy"
  namespace  = kubernetes_namespace.monitoring.id
  repository = "https://oauth2-proxy.github.io/manifests"
  chart      = "oauth2-proxy"
  version    = "6.2.1"

  values = [
    data.template_file.kibana_audit_proxy.rendered,
  ]

  depends_on = [
    random_id.session_secret,
    kubernetes_namespace.monitoring
  ]

  lifecycle {
    ignore_changes = [keyring]
  }
}

# Kibana_live

data "template_file" "kibana_proxy" {
  template = file("${path.module}/templates/oauth2-proxy.yaml.tpl")

  vars = {
    upstream = var.kibana_upstream
    hostname = terraform.workspace == local.live_workspace ? format("%s.%s", "kibana", local.live_domain) : format(
      "%s.%s",
      "kibana",
      var.cluster_domain_name,
    )
    exclude_paths    = "^/-/healthy$"
    issuer_url       = var.oidc_issuer_url
    client_id        = var.oidc_components_client_id
    client_secret    = var.oidc_components_client_secret
    cookie_secret    = random_id.session_secret.b64_std
    ingress_redirect = false
    clusterName      = terraform.workspace
  }
}

resource "helm_release" "kibana_proxy" {
  count      = var.enable_kibana_proxy ? 1 : 0
  name       = "kibana-proxy"
  namespace  = kubernetes_namespace.monitoring.id
  repository = "https://oauth2-proxy.github.io/manifests"
  chart      = "oauth2-proxy"
  version    = "6.2.1"

  values = [
    data.template_file.kibana_proxy.rendered,
  ]

  depends_on = [
    random_id.session_secret,
    kubernetes_namespace.monitoring
  ]

  lifecycle {
    ignore_changes = [keyring]
  }
}

# Thanos

data "template_file" "thanos_proxy" {
  template = file("${path.module}/templates/oauth2-proxy.yaml.tpl")

  vars = {
    upstream = "http://thanos-query-frontend:9090"
    hostname = format(
      "%s.%s",
      "thanos",
      var.cluster_domain_name,
    )
    exclude_paths        = "^/-/healthy$"
    issuer_url           = var.oidc_issuer_url
    client_id            = var.oidc_components_client_id
    client_secret        = var.oidc_components_client_secret
    cookie_secret        = random_id.session_secret.b64_std
    clusterName          = terraform.workspace
    ingress_redirect     = local.ingress_redirect
    live_domain_hostname = "thanos.${local.live_domain}"
  }
}

resource "helm_release" "thanos_proxy" {
  name       = "thanos-proxy"
  namespace  = "monitoring"
  repository = "https://oauth2-proxy.github.io/manifests"
  chart      = "oauth2-proxy"
  version    = "6.2.1"

  values = [
    data.template_file.thanos_proxy.rendered,
  ]

  depends_on = [
    random_id.session_secret
  ]

  lifecycle {
    ignore_changes = [keyring]
  }
}