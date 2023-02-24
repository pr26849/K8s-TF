locals {
  app_data = jsondecode(file("applications.json"))
  apps = { for obj in local.app_data.applications : "${obj.name}" => obj }
}

resource "kubernetes_deployment" "f_cloud_deployment" {
  for_each = local.apps
  metadata {
    name = each.value.name
    labels = {
      app = each.value.name
    }
  }

  spec {
    replicas = each.value.replicas
    selector {
      match_labels = {
        app = each.value.name
      }
    }

    template {
      metadata {
        labels = {
          app = each.value.name
        }
      }

      spec {
        container {
          image = each.value.image
          name  = each.value.name
          args  = [each.value.args]
          port {
            container_port = each.value.port
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "f_cloud_service" {
  depends_on = [resource.kubernetes_deployment.f_cloud_deployment]
  for_each = local.apps
  metadata {
    name = "${each.value.name}-service"
    labels = {
      app = each.value.name
    }
  }
  spec {
    selector = {
      app = each.value.name
    }
    port {
      port        = each.value.port
      target_port = each.value.port
    }
    type = "NodePort"
  }
}

resource "kubernetes_ingress_v1" "f_cloud_ingress" {
  depends_on = [resource.kubernetes_service.f_cloud_service]
  for_each = local.apps
  wait_for_load_balancer = true
  metadata {
    name = "${each.value.name}-canary-ingress"
	annotations = {
      "kubernetes.io/ingress.class" = "nginx"
      "nginx.ingress.kubernetes.io/canary" = "true"
      "nginx.ingress.kubernetes.io/canary-weight" = "100"
      "kubernetes.io/elb.port" = "80"
    }
  }
  spec {
    ingress_class_name = "nginx"
    rule {
      http {
        path {
          path = "/*"
          backend {
            service {
              name = "${each.value.name}-service"
              port {
                number = each.value.port
              }
            }
          }
        }
      }
    }
  }
}