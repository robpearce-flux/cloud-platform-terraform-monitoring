# Grafana secrets
resource "kubernetes_secret" "grafana_secret" {
  metadata {
    name      = "grafana-env"
    namespace = kubernetes_namespace.monitoring.id
  }

  data = {
    GF_AUTH_GENERIC_OAUTH_CLIENT_ID     = var.oidc_components_client_id
    GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET = var.oidc_components_client_secret
    GF_AUTH_GENERIC_OAUTH_AUTH_URL      = "${var.oidc_issuer_url}authorize"
    GF_AUTH_GENERIC_OAUTH_TOKEN_URL     = "${var.oidc_issuer_url}oauth/token"
    GF_AUTH_GENERIC_OAUTH_API_URL       = "${var.oidc_issuer_url}userinfo"
  }

  type = "Opaque"
}

resource "random_id" "username" {
  byte_length = 8
}

resource "random_id" "password" {
  byte_length = 8
}

data "template_file" "alertmanager_routes" {
  count = length(var.alertmanager_slack_receivers)

  template = <<EOS
- match:
    severity: info-$${severity}
  receiver: slack-info-$${severity}
  continue: true
- match:
    severity: $${severity}
  receiver: slack-$${severity}
EOS


  vars = var.alertmanager_slack_receivers[count.index]
}

data "template_file" "alertmanager_receivers" {
  count = length(var.alertmanager_slack_receivers)

  template = <<EOS
- name: 'slack-$${severity}'
  slack_configs:
  - api_url: "$${webhook}"
    channel: "$${channel}"
    send_resolved: True
    title: '{{ template "slack.cp.title" . }}'
    text: '{{ template "slack.cp.text" . }}'
    footer: ${local.alertmanager_ingress}
    actions:
    - type: button
      text: 'Runbook :blue_book:'
      url: '{{ (index .Alerts 0).Annotations.runbook_url }}'
    - type: button
      text: 'Query :mag:'
      url: '{{ (index .Alerts 0).GeneratorURL }}'
    - type: button
      text: 'Dashboard :chart_with_upwards_trend:'
      url: '{{ (index .Alerts 0).Annotations.dashboard_url }}'
    - type: button
      text: 'Silence :no_bell:'
      url: '{{ template "__alert_silence_link" . }}'
- name: 'slack-info-$${severity}'
  slack_configs:
  - api_url: "$${webhook}"
    channel: "$${channel}"
    send_resolved: False
    title: '{{ template "slack.cp.title" . }}'
    text: '{{ template "slack.cp.text" . }}'
    color: 'good'
    footer: ${local.alertmanager_ingress}
    actions:
    - type: button
      text: 'Query :mag:'
      url: '{{ (index .Alerts 0).GeneratorURL }}'
EOS


  vars = var.alertmanager_slack_receivers[count.index]
}


# Prometheus crd yaml pulled from kube-prometheus-stack helm chart.
# Upate variable `prometheus_operator_crd_version` to manage the crd version
data "http" "prometheus_crd_yamls" {
  for_each = local.prometheus_crd_yamls
  url      = each.value
}

resource "kubectl_manifest" "prometheus_operator_crds" {
  server_side_apply = true
  for_each          = data.http.prometheus_crd_yamls
  yaml_body         = each.value["body"]
}

# NOTE: Make sure to update the correct CRD version(if required) using above resource
# `kubectl_manifest.prometheus_operator_crds` before upgrading prometheus operator
resource "helm_release" "prometheus_operator_eks" {

  name       = "prometheus-operator"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = kubernetes_namespace.monitoring.id
  version    = "41.9.1"
  skip_crds  = true # Crds are managed seperately using resource kubectl_manifest.prometheus_operator_crds

  values = [templatefile("${path.module}/templates/prometheus-operator-eks.yaml.tpl", {
    alertmanager_ingress                       = local.alertmanager_ingress
    grafana_ingress                            = local.grafana_ingress
    grafana_root                               = local.grafana_root
    pagerduty_config                           = var.pagerduty_config
    alertmanager_routes                        = join("", data.template_file.alertmanager_routes[*].rendered)
    alertmanager_receivers                     = join("", data.template_file.alertmanager_receivers[*].rendered)
    prometheus_ingress                         = local.prometheus_ingress
    random_username                            = random_id.username.hex
    random_password                            = random_id.password.hex
    grafana_assumerolearn                      = aws_iam_role.grafana_role.arn
    clusterName                                = terraform.workspace
    enable_prometheus_affinity_and_tolerations = var.enable_prometheus_affinity_and_tolerations
    enable_thanos_sidecar                      = var.enable_thanos_sidecar
    enable_large_nodesgroup                    = var.enable_large_nodesgroup
    eks_service_account                        = module.iam_assumable_role_monitoring.this_iam_role_arn
    storage_class                              = can(regex("live", terraform.workspace)) ? "io1-expand" : "gp2-expand"
    storage_size                               = can(regex("live", terraform.workspace)) ? "750Gi" : "75Gi"
  })]

  # Depends on Helm being installed
  depends_on = [
    local.prometheus_operator_crds_dependency,
    kubernetes_secret.grafana_secret,
    kubernetes_secret.thanos_config,
    kubernetes_secret.dockerhub_credentials
  ]

  provisioner "local-exec" {
    command = "kubectl apply -n monitoring -f ${path.module}/resources/prometheusrule-alerts/"
  }

  # Delete Prometheus leftovers
  # Ref: https://github.com/coreos/prometheus-operator#removal
  provisioner "local-exec" {
    when    = destroy
    command = "kubectl delete svc -l k8s-app=kubelet -n kube-system"
  }

  lifecycle {
    ignore_changes = [keyring]
  }
}

# Alertmanager and Prometheus proxy
# Ref: https://github.com/evry/docker-oidc-proxy
resource "random_id" "session_secret" {
  byte_length = 16
}

# This Ingress is to re-direct "grafana.cloud-platform.service.justice.gov.uk" to grafana_root URL
# GF_SERVER_ROOT_URL supports only one URL, so cannot create multiple hosts as Prometheus and alertmanager in this module.

resource "kubernetes_ingress_v1" "ingress_redirect_grafana" {
  count = local.ingress_redirect ? 1 : 0
  metadata {
    name      = "ingress-redirect-grafana"
    namespace = kubernetes_namespace.monitoring.id
    annotations = {
      "external-dns.alpha.kubernetes.io/aws-weight"     = "100"
      "external-dns.alpha.kubernetes.io/set-identifier" = "dns-grafana"
      "cloud-platform.justice.gov.uk/ignore-external-dns-weight" : "true"
      "nginx.ingress.kubernetes.io/permanent-redirect" = local.grafana_root
    }
  }
  spec {
    ingress_class_name = "default"
    tls {
      hosts = ["grafana.${local.live_domain}"]
    }
    rule {
      host = "grafana.${local.live_domain}"
      http {
        path {
          path = ""
          backend {
            service {
              name = "prometheus-operator-grafana"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}
