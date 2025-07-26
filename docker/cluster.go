// Copyright 2025 Amiasys Corporation and/or its affiliates. All rights reserved.

package main

import (
	"fmt"
	"log"
	"os"
	"strconv"

	"gopkg.in/yaml.v3"
)

type topo struct {
	Networks []*network       `yaml:"networks"`
	Nodes    map[string]*node `yaml:"nodes"`
}

type network struct {
	Name  string   `yaml:"name"`
	Desc  string   `yaml:"desc,omitempty"`
	Nodes []string `yaml:"nodes,omitempty"`
}

type node struct {
	Type    string `yaml:"type"`
	Managed bool   `yaml:"managed"`
}

func main() {
	var n int
	var err error
	if len(os.Args) != 2 {
		log.Println("args error, using default value: 100")
		n = 1
	} else {
		n, err = strconv.Atoi(os.Args[1])
		if err != nil {
			log.Println("args error, using default value: 100")
			n = 1
		}
	}

	// generate controller file
	err = os.MkdirAll("controller", 0755)
	if err != nil {
		panic(err)
	}

	err = os.MkdirAll("controller/config", 0755)
	if err != nil {
		panic(err)
	}

	err = os.MkdirAll("controller/log", 0755)
	if err != nil {
		panic(err)
	}

	err = os.MkdirAll("controller/services", 0755)
	if err != nil {
		panic(err)
	}

	// ASNC conf
	err = os.WriteFile(
		"controller/config/asn.conf",
		[]byte(`# Copyright 2025 Amiasys Corporation and/or its affiliates. All rights reserved.

##
# Mode
#
# Just a flag.
# Configurations should be set accordingly with caution.
mode: "dev" # Mandatory: "dev": development; "pro": production.

# Network Topology
#
# TOPO file is loaded when it's specified. And the networks defined in it will be imported
# if not existing.
#
# Topology-based verification is optional. So the TOPO File, topo_file, is loaded at start., if specified.
# Configurable Topo Verifications:
#  - network: verify the presence of root network
#  - parent: verify the presence of parent (network)
#  - node: verify the presence of the service node. Default setting for all node types. Can be overwritten.
#  - router|switch|appliance|server|*: overwriting "node" verification for THE SPECIFIED TYPE of nodes.
network:
  topo_file: ./config/cluster.yml  # network topology description file path

# Services
#
# Listed service will be loaded at starting.
# The default service file is servicename.so, if not specified.
# TBD: Dynamic loading if needed.
#
# Listed service uses controller's default DBs if not specified.
service:
  - name: myservice
`),
		0644,
	)
	if err != nil {
		panic(err)
	}

	// IAM config
	if err := os.WriteFile(
		"controller/config/iam.yml",
		[]byte(`# Copyright 2025 Amiasys Corporation and/or its affiliates. All rights reserved.

## Log Configurations
#log:
#  level: "info" # Supported log level: panic | fatal | error | warning | info | debug | trace. Default: info
#  file: "/var/log/sapphire/iam.log" # Default: "/var/log/sapphire/iam.log"

## Database Configurations
#db:
#  provider: "mongodb" # Supported: "mongodb" | "filedb". Default: "mongodb"
#  url: "localhost:27017" # Default: "localhost:27017"
#  username: "amia" # Default: "amia"
#  password: "2022" # Default: "2022"

## Services
services: # supported service names
  asn:
    add_existing_accounts: true
  myservice:
    add_existing_accounts: true

## LDAP Configurations
#ldap:
#  enabled: false # Default: false
#  interval: 15 # Sync interval in minutes, Default: 15
#  url: "ldap://localhost:389" # Default: "ldap://localhost:389"
#  base_dn: "dc=amianetworks,dc=com" # Default: "dc=amianetworks,dc=com"
#  password_cn: "cn=admin" # Default: "cn=admin"
#  password: "2022" # Default: "2022"
#  ous:
#    account: "People"
#    group: "Group"
#  defaults:
#    account_shadow_warning: "7" # Default: "7"
#    account_shadow_max: "99999" # Default: "99999"
#    account_home_directory_prefix: "/home/" # Default: "/home/"
#    account_login_shell: "/bin/bash" # Default: "/bin/bash"

## API Configurations
#api:
#  grpc:
#    port: 50426 # gRPC API port. Default:50426
#    tls:
#      enabled: false # Default: false
#      root_ca: "/etc/sapphire/cert/ca.crt"
#      pem_file: "/etc/sapphire/cert/server.pem"
#      key_file: "/etc/sapphire/cert/server.key"

# Lock
#
# Default mode is standalone.
# To config "distributed" mode, uncomment "redis" config section.
#   - Redis "standard" is a single-instance locker
#   - Redis "redlock" is used to implement distributed locks with multiple Redis instance.
#lock:
#  mode: "standalone" # (standalone | distributed) Default: "standalone"
#  waiting_limit: 10 # Default: 10 (Seconds)
#  holding_limit: 5 # Default: 5 (Seconds)
#  redis: # used only in distributed mode
#    mode: "standard" # (standard | redlock) Default: "standard"
#    nodes: # list of redis nodes. Only the first one is used in standard mode
#      urls:
#        - "localhost:6379" # Default: "localhost:6379"
#      passwords:
#        - "2023"
#      dbs:
#        - 0 # index: 0 ~ 15 (Default: 0)

## Email Service
#smtp: # SMTP email server config
#  enabled: false # Default: false
#  tls: true
#  host: "smtp.office365.com"
#  email: "email@amiasys.com"
#  username: "email@amiasys.com"
#  password: ""
#  port: 587

## Account Configurations
#account:
#  special_key: "SpecialAccount@AmiaNetworks2025" # Used to create special accounts which skips MFA.
#  password_algo: argon2id # argon2id | bcrypt | md5 | pbkdf2 | scrypt | sha1 | sha256 | sha512, Default: argon2id
#
#  # Regular expressions are used here to specify the format of username, password, and user group.
#  # ^, $: start-of-line and end-of-line respectively.
#  # [...]: Accept ANY ONE of the character within the square bracket, e.g., [aeiou] matches "a", "e", "i", "o" or "u".
#  # [.-.] (Range Expression): Accept ANY ONE of the character in the range, e.g., [0-9] matches any digit; [A-Za-z] matches any uppercase or lowercase letters.
#  # {m,n}: m to n (both inclusive)
#  # If you need to customize the format, please refer to the regular expression syntax.
#  format:
#    name: "^[0-9a-zA-Z\u4e00-\u9fa5!@$._-]{2,36}$"
#    password: "^[0-9a-zA-Z!@$._-]{6,128}$"
#    email: "^(?:[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,})?$"
#    country_code: "^(?:\\d{1,3})?$"
#    phone: "^(?:$|[\\d\\s\\-\\(\\)\\.]{6,15})$"
#
#  # You can recover the account through email or SMS(TBD).
#  # If none of the above methods are available, the admin can reset the account through the cli command line.
#  # TBD: recover account by SMS
#  recovery:
#    email: # Sending a code to your recovery email # Code format:  "^[0-9a-zA-Z-:.]{6,128}$"
#      expire: 5 # Expiration time in minutes. Default 5 minutes.
#      resend_interval: 1 # Resending interval in minutes. Default 1 minute

## Authentication Configurations
#authentication:
#  service:
#    mtls: false # Default: false
#    client_ca: "/etc/sapphire/cert/ca.crt"
#    name: "^[0-9a-zA-Z_-]{2,36}$"
#
#  # Attempt frequency can limit the frequency of user attempts to log in.
#  attempt_frequency:
#    wait_min: 1 # Minimum wait time after an attempt in second. Default: 1 Seconds
#    wait_max: 43200 # Maximum waiting time after an attempt in second. Default: 43200 Seconds
#    amp_factor: 2 # The waiting time after each failure will be extended according to the amplification factor. Default: 3
#
#  # Config the concurrent authentication to limit the number of concurrent authentication entity allowed per user.
#  # You can configure the maximum number of entities allowed to log in, and if exceeded, it will be handled according to the auto replacement policy.
#  # Supported auto replacement policies: disable | random | oldest | latest. Default: disable
#  concurrent_authentication:
#    entity_allowed: 3 # maximum number of entities allowed, 0 means disable;  less than 0 means login is prohibited. Default: 3
#    auto_replacement: "disable"
#
#  # Configure MFA(Multi-Factor Authentication) information
#  # By using the TOTP(Time-Based One Time Password) method, one time password is created on the user side through a smartphone application.
#  # Applications that are known to work with TOTP： Microsoft Authenticator、Google Authenticator）
#  # TBD: SMS
#  mfa:
#    totp:
#      # The issuer indicates the provider or service this account is associated with, URL-encoded according to RFC 3986.
#      issuer: "Amia Networks Inc."

## Authorization Configurations
#authorization:
#  # JWT（JSON Web Token）is an open source standard (RFC 7519) that defines the format for how communicating parties can exchange information securely.
#  # TBD: JWT provides different token strategies for different entity types
#  jwt:
#    issuer: "amianetworks.com"
#    # RS256 Key Set for JWT signature.
#    # [NOT RECOMMENDED!!!] If either is set to empty, a random set will be used.
#    public_key_file: ""
#    private_key_file: ""
#    access_token:
#      expire: 60   # Access token expiration time in minutes. Default: 60 minutes.
#    refresh_token:
#      enabled: true # Support automatically obtaining access token through refresh token. Default: true
#      expire: 600  # Refresh token expiration time in minutes. Default: 600 minutes.
#
#  access_control:
#    format:
#      role:
#        name: "^[0-9a-zA-Z!@$._-]{6,128}$"
#      policy:
#        name: "^[0-9a-zA-Z\u4e00-\u9fa5!@$._-]{2,36}$"
#        scope: "^[0-9a-zA-Z!@$._-/*?%&]{6,128}$"
#        operation: "^[0-9a-zA-Z!@$._-]{6,128}$"
#        time: "^[0-9a-zA-Z-:.]{6,128}$"

## Group Configurations
#group:
#  name: "^[0-9a-zA-Z\u4e00-\u9fa5!@$._-]{2,36}$"

## Role Configurations
#role:
#  name: "^[0-9a-zA-Z\u4e00-\u9fa5!@$._-]{2,36}$"

## Policy Configurations
#policy:
#  name: "^[0-9a-zA-Z\u4e00-\u9fa5!@$._-]{2,36}$"
`),
		0644,
	); err != nil {
		panic(err)
	}

	// You can decide the topology network
	newNetwork := &network{
		Name: "network1",
		Desc: fmt.Sprintf("Network with %d nodes", n),
	}
	newTopo := topo{
		Networks: []*network{newNetwork},
		Nodes:    map[string]*node{},
	}

	for i := 1; i <= n; i++ {
		nodeName := fmt.Sprintf("node%d", i)
		newNetwork.Nodes = append(newNetwork.Nodes, nodeName)
		newTopo.Nodes[nodeName] = &node{
			Type:    "server",
			Managed: true,
		}
	}

	bytes, err := yaml.Marshal(newNetwork)
	if err != nil {
		panic(err)
	}

	fileName := "controller/config/cluster.yml"
	err = os.WriteFile(fileName, bytes, 0644)
	if err != nil {
		panic(err)
	}

	// ASNC docker compose file
	err = os.WriteFile(
		"controller/asnc.yml",
		[]byte(`# Copyright 2025 Amiasys Corporation and/or its affiliates. All rights reserved.

services:
  asn-mdb:
    container_name: asn-mdb
    image: mongo:8  # the mongodb version
    restart: always   # auto restart the container if it fails
    ulimits:
      nofile: 100000
    environment:
      MONGO_INITDB_ROOT_USERNAME: amia  # db root username,
      MONGO_INITDB_ROOT_PASSWORD: 2022  # db root user password
    ports:
      - "27017:27017"  # port forwarding (localPort:containerPort)
    volumes:
      - mongodb_data:/data/db  # data volumes, (localDirectory:containerDirectory)
    command: --bind_ip_all --auth
  asn-idb:
    image: influxdb:2.7
    container_name: asn-idb
    ports:
      - "8086:8086"
    volumes:
      - influxdb_data:/var/lib/influxdb2
    environment:
      DOCKER_INFLUXDB_INIT_MODE: setup
      DOCKER_INFLUXDB_INIT_USERNAME: amia
      DOCKER_INFLUXDB_INIT_PASSWORD: Amiasys2025
      DOCKER_INFLUXDB_INIT_ORG: amia
      DOCKER_INFLUXDB_INIT_BUCKET: asn
      DOCKER_INFLUXDB_INIT_ADMIN_TOKEN: Amiasys2025
      DOCKER_INFLUXDB_INIT_RETENTION: 0
  sapphire-iam:
    image: registry.amiasys.com/sapphire.iam:25.6.5
    container_name: sapphire-iam
    privileged: true
    restart: always
    depends_on:
      - "asn-mdb"
    network_mode: host
    volumes:
      - ./iam-cert/:/etc/sapphire/cert/
      - ./iam-config/:/etc/sapphire/config/
      - ./iam-log/:/var/log/sapphire/
  asnc:
    restart: always
    image: registry.amiasys.com/asnc:25.7.12
    network_mode: host
    depends_on:
      - "asn-mdb"
      - "asn-idb"
      - "sapphire-iam"
    volumes:
      - ./asn-config/:/asn/config
      - ./asn-log/:/var/log/asn/controller
      - ./asn-services:/usr/local/asn/controller/services
      - ./asn-web:/var/www/asn/controller

volumes:
  mongodb_data:
    driver: local
  influxdb_data:
    driver: local
`),
		0644,
	)
	if err != nil {
		panic(err)
	}

	// make service node files
	err = os.MkdirAll("servicenode", 0755)
	if err != nil {
		panic(err)
	}

	err = os.MkdirAll("servicenode/services", 0755)
	if err != nil {
		panic(err)
	}

	for i := 1; i <= n; i++ {
		fileName = fmt.Sprintf("sn%d", i)
		err = os.MkdirAll("servicenode/"+fileName, 0755)
		if err != nil {
			panic(err)
		}

		err = os.MkdirAll(fmt.Sprintf("servicenode/%s/config", fileName), 0755)
		if err != nil {
			panic(err)
		}

		err = os.MkdirAll(fmt.Sprintf("servicenode/%s/log", fileName), 0755)
		if err != nil {
			panic(err)
		}

		err = os.WriteFile(
			fmt.Sprintf("servicenode/%s/config/asn.conf", fileName),
			[]byte(fmt.Sprintf(`# Copyright 2025 Amiasys Corporation and/or its affiliates. All rights reserved.

# Service Node Info
#
# Template (from Topology Schema)
#  <node-name>:
#    type: router | switch | appliance | firewall | lb | ap | server | endpoint
#    desc: <text>                          # Optional
#    location:                             # Optional
#      desc: <text>                        # Optional
#      tier: <tier-name>                   # Optional (must match location-tiers if set)
#      address: <text>                     # Optional, usually omitted
#      coordinates: {latitude: <float>, longitude: <float>, altitude: <float>} # Optional
#    managed: true | false                 # Default: false
#    hostname: <name.domain>               # Optional
#    hostip: <ip>                          # Optional
#    ipmi:                                 # Optional
#      ip: <ip>
#      username: <text>
#      key: <text>
#    info:                                 # Optional
#      vendor: <text>
#      model: <text>
#      sn: <text>
#    interfaces:                           # Optional
#      <if-name>:
#        ip: <CIDR>
#        tags: [control | data | management]
general:
  mode: "cluster" # cluster | standalone, Default: cluster
  network: "network1" # Root Network to register
  parent: "network1" # Parent Network to register
  node_name: "node%d" # Default: hostname or hostIP
  type: server # router | switch | appliance | firewall | lb | ap | server | device
  managed: true # Default: false
#  hostname: <name.domain> # Required for
#  node_ip: <ip>
#  ipmi:                                 # Optional
#    ip: <ip>
#    username: <text>
#    key: <text>
#  interfaces:                           # Optional but highly recommended
#    <if-name>:
#      ip: <CIDR>
#      tags: data # [control | data | management]

# Certificates
#
cert:
  server_ca: ""
  node_pem: ""
  node_key: ""

# Servnice Node CLI
cli:
  grpc: ":52767" # Default: localhost:52767

# Controller
#
# TBD: retry_interval should be the default interval.
controller:
  #  address: 127.0.0.1:12762 # Default: 127.0.0.1:12762
  retry_interval: 5 # Default: 5 seconds

# Log
#
# Default Log Level is "info", but can be changed for each log.
#log:
#  path: "./log" # Default: "/var/log/asn/"
#  prefix: "asn" # Default: "asn"
#  api_log:
#    filename: "api.log" # Default: "api.log"
#    level: "info"
#  entity_log:
#    filename: "entity.log" # Default: "entity.log"
#    level: "info"
#  perf_log:
#    filename: "perf.log" # Default: "perf.log"
#    level: "info"
#  runtime_log:
#    filename: "runtime.log" # Default: "runtime.log"
#    level: "info"

# Services
#
# Service plugins
service:
  timeout: 10 # Default: 10 seconds
`, i)),
			0644,
		)
		if err != nil {
			panic(err)
		}

		// ASNSN docker compose file
		err = os.WriteFile(
			fmt.Sprintf("servicenode/%s/asnsn.yml", fileName),
			[]byte(`# Copyright 2025 Amiasys Corporation and/or its affiliates. All rights reserved.

services:
  asnsn:
    restart: always
    image: registry.amiasys.com/asnsn:25.7.12
    volumes:
      - ./config/:/asn/config
      - ./log/:/var/log/asn/servicenode
      - ../services:/usr/local/asn/servicenode/services
`),
			0644,
		)
		if err != nil {
			panic(err)
		}
	}

	if err := os.WriteFile(
		"up.sh",
		[]byte(fmt.Sprintf(`#!/bin/bash
cd controller || { echo "Failed to enter controller folder"; exit 1; }
echo "Starting Docker Compose in controller folder..."
docker compose -f asnc.yml up -d || { echo "Failed to execute docker compose in controller folder"; exit 1; }
echo "Docker Compose started in controller folder."
cd - || { echo "Failed to return to the previous directory"; exit 1; }
cd servicenode || { echo "Failed to enter servicenode folder"; exit 1; }
for i in $(seq 1 %d); do
folder="sn$i"
if [ -d "$folder" ]; then
cd "$folder" || { echo "Failed to enter $folder folder"; exit 1; }
echo "Starting Docker Compose in $folder..."
docker compose -f asnsn.yml up -d || { echo "Failed to execute docker compose in $folder"; exit 1; }
echo "Docker Compose started in $folder."
cd - >/dev/null || { echo "Failed to return to servicenode folder"; exit 1; }
else
echo "Folder $folder does not exist, skipping."
fi
done
echo "All tasks completed."`, n)),
		0755,
		); err != nil {
		panic(err)
	}

	if err := os.WriteFile(
		"down.sh",
		[]byte(fmt.Sprintf(`#!/bin/bash
cd controller || { echo "Failed to enter controller folder"; exit 1; }
echo "Starting Docker Compose in controller folder..."
docker compose -f asnc.yml down || { echo "Failed to execute docker compose in controller folder"; exit 1; }
echo "Docker Compose started in controller folder."
cd - || { echo "Failed to return to the previous directory"; exit 1; }
cd servicenode || { echo "Failed to enter servicenode folder"; exit 1; }
for i in $(seq 1 %d); do
folder="sn$i"
if [ -d "$folder" ]; then
cd "$folder" || { echo "Failed to enter $folder folder"; exit 1; }
echo "Starting Docker Compose in $folder..."
docker compose -f asnsn.yml down || { echo "Failed to execute docker compose in $folder"; exit 1; }
echo "Docker Compose started in $folder."
cd - >/dev/null || { echo "Failed to return to servicenode folder"; exit 1; }
else
echo "Folder $folder does not exist, skipping."
fi
done
echo "All tasks completed."`, n)),
		0755,
	); err != nil {
		panic(err)
	}
}
