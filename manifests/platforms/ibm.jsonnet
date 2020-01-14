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

  external_dns_zone_name:: 'k8sibm.gq',

  letsencrypt_contact_email:: $.config.contactEmail,
  letsencrypt_environment:: 'prod',

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

                },

              },
            },
            volumes_+: {
              varlibdockercontainers: kube.HostPathVolume('/var/log/pods', 'Directory'),
            },
          },
        },
      },
    },

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
    ingress+: {
      metadata+: {
        annotations+: {
          'cert-manager.io/issuer': 'letsencrypt-prod',
        },
      },
      local this = self,
      host:: 'kibana.' + $.external_dns_zone_name,
      kibanaPath:: '/',
    },
  },

  config:: {
    contactEmail: error 'Provide the contact email',
    cloudFlareApiKey: error 'Provide the CloudFlare api key',
  },

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
  },

  local flattener(obj) = std.flattenArrays([
    if std.isArray(object) then object else if std.objectHas(object, 'apiVersion') then [object] else flattener(object)
    for object in kube.objectValues(obj)
  ]),

  apiVersion: 'v1',
  kind: 'List',
  items: flattener($.fluentd_es) + flattener($.elasticsearch) + flattener($.kibana) + std.sort(flattener($.cert_manager), function(x) if x.kind == 'CustomResourceDefinition' then 0 else 1),

}
