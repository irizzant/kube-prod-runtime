// Libreria contenente le funzioni e gli oggetti per lavorare con Istio

local kube = import '../../lib/kube.libsonnet';

local istioPortName(portNumber, portName) = if portNumber == 80 then 'http' else if portNumber == 443 then 'https' else portName;

local newIstioTLSTrafficPolicy(mode='ISTIO_MUTUAL') = {
  trafficPolicy: {
    tls: {
      mode: mode,
    },
  },
};

{
  IstioService(name):: kube._Object('v1', 'Service', name) {
    local this = self,

    source_:: error 'source not provided',

    spec: {
      selector: this.source_.metadata.labels,
      ports: [
        {
          port: 80,
          name: 'tcp',
          targetPort: 80,
        },
      ],
      type: 'ClusterIP',
    },
  },

  Gateway(name):: kube._Object('networking.istio.io/v1alpha3', 'Gateway', name) {
    local this = self,

    servers_:: error 'servers_ not provided',

    spec: {
      selector: {
        istio: 'ingressgateway',
      },

      servers: [
        this.servers_[server]
        for server in std.objectFields(this.servers_)
      ],
    },

  },

  VirtualService(name):: kube._Object('networking.istio.io/v1alpha3', 'VirtualService', name) {

    local this = self,

    hosts:: error 'hosts not provided',

    httpRoutes_:: {},

    tlsRoutes_:: {},

    tcpRoutes_:: {},

    gateways_:: [],

    spec: {

      hosts: this.hosts,

      gateways: this.gateways_,

      http: [
        this.httpRoutes_[route]
        for route in std.objectFields(this.httpRoutes_)
      ],

      tls: [
        this.tlsRoutes_[route]
        for route in std.objectFields(this.tlsRoutes_)
      ],

      tcp: [
        this.tcpRoutes_[route]
        for route in std.objectFields(this.tcpRoutes_)
      ],
    },


  },

  DestinationRule(name):: kube._Object('networking.istio.io/v1alpha3', 'DestinationRule', name) {

    local this = self,

    host:: error 'host is not provided',

    virtualService_:: null,

    spec: {
      host: this.host,

      subsets: if this.virtualService_ != null then (
        [
          {
            name: route.destination.subset,
          }
          for httpRoute in this.virtualService_.http
          for route in httpRoute.route
          if route.destination.host == this.host
          if std.objectHas(route.destination, 'subset')
        ] + [
          {
            name: route.destination.subset,
          }
          for tlsRoute in this.virtualService_.tls
          for route in tlsRoute.route
          if route.destination.host == this.host
          if std.objectHas(route.destination, 'subset')
        ] + [
          {
            name: route.destination.subset,
          }
          for tcpRoute in this.virtualService_.tcp
          for route in tcpRoute.route
          if route.destination.host == this.host
          if std.objectHas(route.destination, 'subset')
        ]
      ) else [],
    },

  },

  newIstioTLSTrafficPolicy:: newIstioTLSTrafficPolicy,

  gwTest:: $.Gateway('test') {
    servers_: {
      kibana: {
        port: {
          number: 80,
          name: 'kibana',
          protocol: 'HTTP',
        },

        hosts: [
          'kibana.test.io',
        ],
      },
    },
  },

  vsTest:: $.VirtualService('test') {
    hosts: ['*'],
    gateways_: ['test'],
    httpRoutes_:: {
      testHttpRoute: {
        route: [
          {
            destination: {
              host: 'a',
              subset: 'v1',
            },
          },
        ],
      },
    },

    tcpRoutes_:: {
      tcpRoutes_: {
        route: [
          {
            destination: {
              host: 'b',
              subset: 'v2',
              port: {
                number: 5601,
              },
            },
          },
        ],
      },
    },
  },

  drTestA:: $.DestinationRule('test') {

    host: 'a',

    virtualService_:: $.vsTest,

  },

  drTestB:: $.DestinationRule('test') {

    host: 'b',

    virtualService_:: $.vsTest,

  },
}
