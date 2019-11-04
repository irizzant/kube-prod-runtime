local cert_manager = import '../components/cert-manager.jsonnet';
local elasticsearch = import '../components/elasticsearch.jsonnet';
local edns = import '../components/externaldns.jsonnet';
local fluentd_es = import '../components/fluentd-es.jsonnet';
local grafana = import '../components/grafana.jsonnet';
local kibana = import '../components/kibana.jsonnet';
local nginx_ingress = import '../components/nginx-ingress.jsonnet';
local oauth2_proxy = import '../components/oauth2-proxy.jsonnet';
local prometheus = import '../components/prometheus.jsonnet';
local version = import '../components/version.jsonnet';
local kube = import '../lib/kube.libsonnet';
local utils = import '../lib/utils.libsonnet';

{
  // Shared metadata for all components
  kubeprod:: kube.Namespace('kubeprod'),

  external_dns_zone_name:: 'sdbfi-k8s-kubespray.sdb.it',

  version:: version,

  config:: {
    oauthProxy: {
      client_id: '322845a8fc9d6dff9c2066c2b4bf6bda1a51f8707a66af4aa0209d583bc203a2',
      client_secret: 'd7752d348b9b1cce604501d67f4cbf34453b81c4985003bee99b2facb56d8889',
      cookie_secret: 'DtfhDfi6CXT6ggaOyNKE/wVtDPgKE16htn6WzJelIGs=',
    },
  },

  oauth2_proxy:: oauth2_proxy {
    secret+: {
      data_+: $.config.oauthProxy,
    },

    ingress+: kube.Ingress($.oauth2_proxy.p + 'oauth2-ingress') + $.oauth2_proxy.metadata {
      local this = self,
      host: 'auth.' + $.external_dns_zone_name,

      spec+: {
        rules+: [{
          host: this.host,
          http: {
            paths: [
              { path: '/oauth2/', backend: $.oauth2_proxy.svc.name_port },
            ],
          },
        }],
      },
    },


    deploy+: {
      spec+: {
        template+: {
          spec+: {
            containers_+: {
              proxy+: {
                local gitlabUrl = 'http://sdbit-git.sdb.it',
                args_+: {
                  'redirect-url': 'http://%s/oauth2/callback' % $.oauth2_proxy.ingress.host,
                  provider: 'gitlab',
                  'login-url': '%s/oauth/authorize' % gitlabUrl,
                  'redeem-url': '%s/oauth/token' % gitlabUrl,
                  'validate-url': '%s/api/v4/user' % gitlabUrl,
                  'oidc-issuer-url': gitlabUrl,
                  'cookie-secure': 'false',
                },
              },
            },
          },
        },
      },
    },
  },


  grafana:: grafana {
    prometheus:: $.prometheus.prometheus.svc,
    ingress+: kube.Ingress($.grafana.p + 'prometheus') + $.grafana.metadata {
      local this = self,
      host:: 'grafana.' + $.external_dns_zone_name,
      prom_path:: '/',
      am_path:: '/alertmanager',
      prom_url:: 'http://%s%s' % [this.host, self.prom_path],
      am_url:: 'http://%s%s' % [this.host, self.am_path],
      spec+: {
        rules+: [
          {
            host: this.host,
            http: {
              paths: [
                { path: this.prom_path, backend: $.prometheus.svc.name_port },
                { path: this.am_path, backend: $.alertmanager.svc.name_port },
              ],
            },
          },
        ],
      },
    },
  },

  prometheus:: prometheus {
    retention_days:: 7,
    ingress+: kube.Ingress($.prometheus.p + 'prometheus') + $.prometheus.metadata {
      local this = self,
      host:: 'prometheus.' + $.external_dns_zone_name,
      prom_path:: '/',
      am_path:: '/alertmanager',
      prom_url:: 'http://%s%s' % [this.host, self.prom_path],
      am_url:: 'http://%s%s' % [this.host, self.am_path],
      spec+: {
        rules+: [
          {
            host: this.host,
            http: {
              paths: [
                { path: this.prom_path, backend: $.prometheus.svc.name_port },
                { path: this.am_path, backend: $.alertmanager.svc.name_port },
              ],
            },
          },
        ],
      },
    },
  },


  fluentd_es:: fluentd_es {
    es:: $.elasticsearch,
  },

  elasticsearch:: elasticsearch {
    sts+: {
      spec+: {
        volumeClaimTemplates_+: {
          data: { storage: '100Mi' },
        },
      },
    },
    curator+: {
      retention:: 5,
    },
  },

  kibana:: kibana {
    es:: $.elasticsearch,
  } + {
    ingress: kube.Ingress($.kibana.p + 'kibana-logging') + $.kibana.metadata {
      local this = self,
      host:: 'kibana.' + $.external_dns_zone_name,
      kibanaPath:: '/',
      spec+: {
        rules+: [
          {
            host: this.host,
            http: {
              paths: [
                { path: this.kibanaPath, backend: $.kibana.svc.name_port },
              ],
            },
          },
        ],
      },
    },
  },

  local flattener(obj) = std.flattenArrays([
    if std.objectHas(object, 'apiVersion') then [object] else flattener(object)
    for object in kube.objectValues(obj)
  ]),

  apiVersion: 'v1',
  kind: 'List',
  items: flattener($.fluentd_es) + flattener($.elasticsearch) + flattener($.kibana) + flattener($.oauth2_proxy)
         + flattener($.grafana) + flattener($.prometheus),

}
