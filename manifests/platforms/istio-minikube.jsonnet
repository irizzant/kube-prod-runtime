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
local istio = import 'istio/istio.libsonnet';

{
  // Shared metadata for all components
  kubeprod:: kube.Namespace('kubeprod'),

  external_dns_zone_name:: '127.0.0.1.nip.io',

  version:: version,

  fluentd_es:: fluentd_es {
    metadata+:: {
      metadata+: {
        labels+: {
          app: 'fluentd-es',
          version: 'v1',
        },
      },
    },
    es:: $.elasticsearch,
    svc: istio.IstioService(fluentd_es.p + 'fluentd-es') + fluentd_es.metadata + {
      source_:: fluentd_es.daemonset,
    },
  },

  elasticsearch:: elasticsearch {
    metadata+:: {
      metadata+: {
        labels+: {
          app: 'elasticsearch',
          version: 'v1',
        },
      },
    },
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
    svc+: {
      spec+: {
        ports: [
          {
            port: p.port,
            name: 'http',
            targetPort: p.targetPort,
          }
          for p in elasticsearch.svc.spec.ports
        ],
      },
    },
  },

  kibana:: kibana {
    es:: $.elasticsearch,
  } + {
    metadata+:: {
      metadata+: {
        labels+: {
          app: 'kibana',
          version: 'v1',
        },
      },
    },
    svc+: {
      spec+: {
        ports: [
          {
            port: p.port,
            name: 'http',
            targetPort: p.targetPort,
          }
          for p in kibana.svc.spec.ports
        ],
      },
    },
    ingress:: kube.Ingress($.kibana.p + 'kibana-logging') + $.kibana.metadata + {
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

  metadata:: {
    metadata+: {
      namespace: 'kubeprod',
    },
  },

  gateway:: istio.Gateway('kibana') + $.metadata + {
    servers_: {
      kibana: {
        port: {
          number: 80,
          name: 'kibana',
          protocol: 'HTTP',
        },

        hosts: [
          'kibana.127.0.0.1.nip.io',
        ],
      },
    },
  },

  virtualService:: istio.VirtualService('kibana') + $.metadata + {
    hosts: ['kibana.127.0.0.1.nip.io'],
    gateways_:: ['kibana'],
    httpRoutes_:: {
      kibanaRoute: {
        route: [
          {
            destination: {
              host: 'kibana-logging.kubeprod.svc.cluster.local',
              port: {
                number: 5601,
              },
            },
          },
        ],
      },
    },
  },

  destinationRule:: istio.DestinationRule('elasticsearch') + $.metadata + {

    host: 'elasticsearch-logging.kubeprod.svc.cluster.local',

    spec+: istio.newIstioTLSTrafficPolicy(),

  },

  config:: config,

  local flattener(obj) = std.flattenArrays([
    if std.isArray(object) then object else if std.objectHas(object, 'apiVersion') then [object] else flattener(object)
    for object in kube.objectValues(obj)
  ]),

  local sortCrds(arr) = std.sort(arr, function(x) if x.kind == 'CustomResourceDefinition' then 0 else 1),

  apiVersion: 'v1',
  kind: 'List',
  items: flattener($.fluentd_es) + flattener($.elasticsearch) + flattener($.kibana) + [$.gateway, $.virtualService, $.destinationRule],

}
