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
local config = import 'config-ibm.jsonnet';

{
  // Shared metadata for all components
  kubeprod:: kube.Namespace('kubeprod'),

  external_dns_zone_name:: 'k8sibm.gq',

  letsencrypt_contact_email:: $.config.contactEmail,
  letsencrypt_environment:: 'staging',

  version:: version,

  fluentd_es:: fluentd_es {
    es:: $.elasticsearch,

    daemonset+: {
      spec+: {
        template+: $.fluentd_es.criticalPod {
          spec+: {
            containers_+: {
              fluentd_es+: {

                volumeMounts_+: {
                  varlogpods: {
                    mountPath: '/var/log/pods',
                    readOnly: true,
                  },
                },

              },
            },
            volumes_+: {
              varlibdockercontainers: kube.HostPathVolume('/var/lib/docker/containers', 'DirectoryOrCreate'),
              varlogpods: kube.HostPathVolume('/var/log/pods', 'Directory'),
            },
          },
        },
      },
    },

    fluentd_es_configd+: {
      data+: {
        'system.input.conf': (importstr 'fluentd-es-config-ibm/system.input.conf'),
      },
    },

  },

  elasticsearch:: elasticsearch {
    sts+: {
      spec+: {
        volumeClaimTemplates_+: {
          data: {
            storage: '10Gi',
            storageClassName: 'rook-ceph-block',
          },
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
    ingress+: {
      metadata+: {
        annotations+: {
          'cert-manager.io/issuer': 'letsencrypt-staging',
        },
      },
      local this = self,
      host:: 'kibana.' + $.external_dns_zone_name,
      kibanaPath:: '/',
    },
  },

  config:: config,

  cert_manager:: cert_manager {
    letsencrypt_contact_email:: $.letsencrypt_contact_email,
    letsencrypt_environment:: $.letsencrypt_environment,

    cloudFlareSecret: kube.Secret($.cert_manager.p + 'cloudflare-api-key-secret') + $.cert_manager.metadata {
      data+: {
        'api-key': std.base64($.config.cloudFlareApiKey),
      },
    },

    letsencryptProd+: cert_manager.letsencryptProd {
      local this = self,
      metadata+: { name: $.cert_manager.p + 'letsencrypt-prod' },
      spec+: {
        acme+: {
          email: $.cert_manager.letsencrypt_contact_email,
          privateKeySecretRef: { name: this.metadata.name },
          solvers: [
            {
              dns01: {
                cloudflare: {
                  email: $.cert_manager.letsencrypt_contact_email,
                  apiKeySecretRef: {
                    name: 'cloudflare-api-key-secret',
                    key: 'api-key',
                  },
                },
              },
            },
          ],
        },
      },
    },
    
    letsencryptStaging+: cert_manager.letsencryptStaging {
      local this = self,
      metadata+: { name: $.cert_manager.p + 'letsencrypt-staging' },
      spec+: {
        acme+: {
          email: $.cert_manager.letsencrypt_contact_email,
          privateKeySecretRef: { name: this.metadata.name },
          solvers: [
            {
              dns01: {
                cloudflare: {
                  email: $.cert_manager.letsencrypt_contact_email,
                  apiKeySecretRef: {
                    name: 'cloudflare-api-key-secret',
                    key: 'api-key',
                  },
                },
              },
            },
          ],
        },
      },
    },
  },

  local flattener(obj) = std.flattenArrays([
    if std.isArray(object) then object else if std.objectHas(object, 'apiVersion') then [object] else flattener(object)
    for object in kube.objectValues(obj)
  ]),

  local sortCrds(arr) = std.sort(arr, function(x) if x.kind == 'CustomResourceDefinition' then 0 else 1),

  apiVersion: 'v1',
  kind: 'List',
  items: flattener($.fluentd_es) + flattener($.elasticsearch) + flattener($.kibana) + sortCrds(flattener($.cert_manager)),

}
