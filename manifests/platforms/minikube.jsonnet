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

  external_dns_zone_name:: '127.0.0.1.nip.io',

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
  
  config:: config,

  local flattener(obj) = std.flattenArrays([
    if std.objectHas(object, 'apiVersion') then [object] else flattener(object)
    for object in kube.objectValues(obj)
  ]),

  apiVersion: 'v1',
  kind: 'List',
  items: flattener($.fluentd_es) + flattener($.elasticsearch) + flattener($.kibana),

}
