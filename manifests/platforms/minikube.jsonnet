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
local config = import 'config-minikube.jsonnet';


{
  // Shared metadata for all components
  kubeprod:: kube.Namespace('kubeprod'),

  external_dns_zone_name:: '192.168.99.100.nip.io',

  version:: version,

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
      retention:: 1,
    },
  },

  kibana:: kibana {
    es:: $.elasticsearch,
  } + {
    ingress: kube.Ingress($.kibana.p + 'kibana-logging') + $.kibana.metadata + {
      local this = self,
      host:: 'kibana.' + $.external_dns_zone_name,
      authHost:: 'auth.' + utils.parentDomain(this.host),
      kibanaPath:: '/',
      metadata+: {
        annotations+: {
          'ingress.kubernetes.io/oauth': 'oauth2_proxy',
        },
      },
      spec+: {
        rules+: [
          {
            host: this.host,
            http: {
              paths: [
                { path: this.kibanaPath, backend: $.kibana.svc.name_port },
                { path: this.kibanaPath + 'oauth2', backend: $.oauth2_proxy.svc.name_port },
              ],
            },
          },
        ],
      },
    },
  },

  config:: config,

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
                args_+: {
                  'redirect-url': '/oauth2/callback',
                  provider: 'github',
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
    ingress+: kube.Ingress($.grafana.p + 'grafana') + $.grafana.metadata {
      local this = self,
      host: 'grafana.' + $.external_dns_zone_name,
      spec+: {
        rules+: [
          {
            host: this.host,
            http: {
              paths: [
                { path: '/', backend: $.grafana.svc.name_port },
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
                { path: this.prom_path, backend: $.prometheus.prometheus.svc.name_port },
                { path: this.am_path, backend: $.prometheus.alertmanager.svc.name_port },
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
  items: flattener($.fluentd_es) + flattener($.elasticsearch) + flattener($.kibana) + flattener($.oauth2_proxy) + flattener($.grafana) + flattener($.prometheus),

}
